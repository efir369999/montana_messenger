#![allow(clippy::doc_overindented_list_items)]

//! Noise_PQ — post-quantum handshake state machine for the Montana network
//! transport layer.
//!
//! Pattern: XK-like 3-message exchange with ML-KEM-768 as the KEM replacement
//! for Diffie-Hellman, and ML-DSA-65 for identity authentication.
//!
//! - msg1 (initiator → responder):
//!   ke_pk     1184 B   — initiator ephemeral ML-KEM-768 public key
//!   ct_rs     1088 B   — encapsulation of fresh shared secret to the
//!                          responder's static ML-KEM-768 public key
//!   Total: 2272 B
//!
//! - msg2 (responder → initiator):
//!   ct_e      1088 B   — encapsulation to ke_pk (ephemeral)
//!   rs_id_pk  1952 B   — responder static ML-DSA-65 identity public key
//!   sig_r     3309 B   — ML-DSA-65 signature by rs_id over transcript
//!                          hash (ke_pk || ct_rs || ct_e)
//!   Total: 6349 B
//!
//! - msg3 (initiator → responder):
//!   is_id_pk  1952 B   — initiator static ML-DSA-65 identity public key
//!   sig_i     3309 B   — ML-DSA-65 signature by is_id over transcript
//!                          hash (ke_pk || ct_rs || ct_e || rs_id_pk || is_id_pk)
//!   Total: 5261 B
//!
//! Final session keys derived via HKDF-style construction over SHA-256:
//!   master = SHA-256("mt-noise-pq-v1-master" || ss_rs || ss_e || transcript)
//!   SK_tx_i_to_r = SHA-256("mt-noise-pq-v1-i2r" || master)
//!   SK_tx_r_to_i = SHA-256("mt-noise-pq-v1-r2i" || master)
//!
//! Identity authentication is provided by the ML-DSA-65 signatures on
//! transcripts that bind both ephemeral and static material; FIPS 203
//! implicit-rejection in decap is reconciled by the identity signature
//! check on the responder side (a maliciously substituted ciphertext
//! gives a different ss_rs, the transcript hash differs, sig_r fails).
//!
//! This module is internal-tested via [`tests::handshake_roundtrip`] and
//! [`tests::tamper_detection_msg2`]; KAT byte-exact vectors are written
//! in `tests/handshake_kat.rs`.

/// NON-PRODUCTION. Legacy XK-pattern libp2p upgrade (initiator pre-knows the
/// responder static ML-KEM key). Production transport uses [`xx_libp2p_upgrade`]
/// (Noise_PQ XX, post-decap shared-secret signature binding per Network v1.4.0).
pub mod libp2p_upgrade;
pub mod stream;
pub mod xx_handshake;
pub mod xx_libp2p_upgrade;

use mt_crypto::{
    keypair_from_seed_mlkem, mlkem_decapsulate, mlkem_encapsulate, sign, verify, MlkemCiphertext,
    MlkemPublicKey, MlkemSecretKey, PublicKey, SecretKey, Signature, MLKEM_CIPHERTEXT_SIZE,
    MLKEM_PUBLIC_KEY_SIZE, PUBLIC_KEY_SIZE, SIGNATURE_SIZE,
};
use sha2::{Digest, Sha256};
use zeroize::Zeroize;

/// Wire size of the Noise_PQ message 1.
pub const NOISE_PQ_MSG1_SIZE: usize = MLKEM_PUBLIC_KEY_SIZE + MLKEM_CIPHERTEXT_SIZE;
/// Wire size of the Noise_PQ message 2.
pub const NOISE_PQ_MSG2_SIZE: usize = MLKEM_CIPHERTEXT_SIZE + PUBLIC_KEY_SIZE + SIGNATURE_SIZE;
/// Wire size of the Noise_PQ message 3.
pub const NOISE_PQ_MSG3_SIZE: usize = PUBLIC_KEY_SIZE + SIGNATURE_SIZE;

/// Length of each derived directional session key in bytes.
pub const NOISE_PQ_SESSION_KEY_SIZE: usize = 32;

const DOMAIN_MASTER: &[u8] = b"mt-noise-pq-v1-master";
const DOMAIN_I2R: &[u8] = b"mt-noise-pq-v1-i2r";
const DOMAIN_R2I: &[u8] = b"mt-noise-pq-v1-r2i";
const SIG_DOMAIN_RESPONDER: &[u8] = b"mt-noise-pq-v1-sig-r";
const SIG_DOMAIN_INITIATOR: &[u8] = b"mt-noise-pq-v1-sig-i";

/// Errors that can occur during a Noise_PQ handshake.
#[derive(Debug, Clone, Eq, PartialEq)]
pub enum NoisePqError {
    BadMsgSize { expected: usize, actual: usize },
    DecapFailed,
    EncapFailed,
    RngFailed,
    BadResponderSignature,
    BadInitiatorSignature,
    InvalidPublicKey,
    InvalidCiphertext,
    Crypto(mt_crypto::CryptoError),
}

impl From<mt_crypto::CryptoError> for NoisePqError {
    fn from(e: mt_crypto::CryptoError) -> Self {
        NoisePqError::Crypto(e)
    }
}

/// Derived session keys (one per direction) plus the transcript hash that
/// can be exposed to higher layers as a channel-binding token.
pub struct NoisePqSession {
    /// Initiator → responder transmission key.
    pub sk_i_to_r: [u8; NOISE_PQ_SESSION_KEY_SIZE],
    /// Responder → initiator transmission key.
    pub sk_r_to_i: [u8; NOISE_PQ_SESSION_KEY_SIZE],
    /// Transcript hash for channel binding.
    pub transcript_hash: [u8; 32],
}

impl Drop for NoisePqSession {
    fn drop(&mut self) {
        self.sk_i_to_r.zeroize();
        self.sk_r_to_i.zeroize();
        self.transcript_hash.zeroize();
    }
}

/// Initiator-side state after sending message 1 and before receiving message 2.
pub struct InitiatorMsg1Sent {
    ke_sk: MlkemSecretKey,
    ke_pk_bytes: [u8; MLKEM_PUBLIC_KEY_SIZE],
    ct_rs_bytes: [u8; MLKEM_CIPHERTEXT_SIZE],
    ss_rs: [u8; 32],
    is_id_sk: SecretKey,
    is_id_pk: PublicKey,
}

/// Initiator-side state after receiving message 2 and before sending message 3.
pub struct InitiatorMsg2Received {
    transcript: Vec<u8>,
    session: NoisePqSession,
    is_id_sk: SecretKey,
    is_id_pk: PublicKey,
}

/// Initiator: send message 1.
///
/// Generates a fresh ephemeral ML-KEM-768 keypair, encapsulates against the
/// responder's static ML-KEM-768 public key, and returns the wire bytes.
pub fn initiator_send_msg1(
    rs_static_pk: &MlkemPublicKey,
    is_id_sk: SecretKey,
    is_id_pk: PublicKey,
) -> Result<(Vec<u8>, InitiatorMsg1Sent), NoisePqError> {
    let mut ephemeral_seed = [0u8; mt_crypto::MLKEM_SEED_SIZE];
    // Fresh OS entropy populates the FIPS 203 §6.1 (d || z, 64B) seed
    // directly. getrandom fails only on platforms without an entropy
    // source available, which is not a supported Montana operator
    // environment.
    getrandom::getrandom(&mut ephemeral_seed).map_err(|_| NoisePqError::RngFailed)?;
    let (ke_pk, ke_sk) = keypair_from_seed_mlkem(&ephemeral_seed)?;
    ephemeral_seed.zeroize();

    let (ct_rs, ss_rs) = mlkem_encapsulate(rs_static_pk)?;

    let mut wire = Vec::with_capacity(NOISE_PQ_MSG1_SIZE);
    wire.extend_from_slice(ke_pk.as_bytes());
    wire.extend_from_slice(ct_rs.as_bytes());

    let mut ss_rs_bytes = [0u8; 32];
    ss_rs_bytes.copy_from_slice(ss_rs.as_bytes());

    let state = InitiatorMsg1Sent {
        ke_sk,
        ke_pk_bytes: *ke_pk.as_bytes(),
        ct_rs_bytes: *ct_rs.as_bytes(),
        ss_rs: ss_rs_bytes,
        is_id_sk,
        is_id_pk,
    };
    Ok((wire, state))
}

/// Initiator: receive message 2 and derive the session keys.
///
/// Decapsulates the responder's reply, derives session keys via HKDF-style
/// construction, and verifies the responder's identity signature over the
/// transcript hash. On signature failure the handshake aborts and returns
/// `BadResponderSignature`.
pub fn initiator_receive_msg2(
    msg2: &[u8],
    state: InitiatorMsg1Sent,
) -> Result<InitiatorMsg2Received, NoisePqError> {
    if msg2.len() != NOISE_PQ_MSG2_SIZE {
        return Err(NoisePqError::BadMsgSize {
            expected: NOISE_PQ_MSG2_SIZE,
            actual: msg2.len(),
        });
    }

    let (ct_e_slice, rest) = msg2.split_at(MLKEM_CIPHERTEXT_SIZE);
    let (rs_id_pk_slice, sig_r_slice) = rest.split_at(PUBLIC_KEY_SIZE);

    let ct_e = MlkemCiphertext::from_slice(ct_e_slice).ok_or(NoisePqError::InvalidCiphertext)?;
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

    let ss_e = mlkem_decapsulate(&state.ke_sk, &ct_e)?;

    let mut transcript =
        Vec::with_capacity(MLKEM_PUBLIC_KEY_SIZE + MLKEM_CIPHERTEXT_SIZE + MLKEM_CIPHERTEXT_SIZE);
    transcript.extend_from_slice(&state.ke_pk_bytes);
    transcript.extend_from_slice(&state.ct_rs_bytes);
    transcript.extend_from_slice(ct_e_slice);

    let transcript_for_sig = Sha256::new()
        .chain_update(SIG_DOMAIN_RESPONDER)
        .chain_update(&transcript)
        .finalize();
    let transcript_for_sig: [u8; 32] = transcript_for_sig.into();

    if !verify(&rs_id_pk, &transcript_for_sig, &sig_r) {
        return Err(NoisePqError::BadResponderSignature);
    }

    let mut master_input = Vec::with_capacity(32 + 32 + transcript.len() + PUBLIC_KEY_SIZE);
    master_input.extend_from_slice(&state.ss_rs);
    master_input.extend_from_slice(ss_e.as_bytes());
    master_input.extend_from_slice(&transcript);
    master_input.extend_from_slice(rs_id_pk.as_bytes());
    let master = Sha256::new()
        .chain_update(DOMAIN_MASTER)
        .chain_update(&master_input)
        .finalize();
    master_input.zeroize();
    let master_bytes: [u8; 32] = master.into();

    let sk_i_to_r_h = Sha256::new()
        .chain_update(DOMAIN_I2R)
        .chain_update(master_bytes)
        .finalize();
    let sk_r_to_i_h = Sha256::new()
        .chain_update(DOMAIN_R2I)
        .chain_update(master_bytes)
        .finalize();
    let mut sk_i_to_r = [0u8; 32];
    sk_i_to_r.copy_from_slice(&sk_i_to_r_h);
    let mut sk_r_to_i = [0u8; 32];
    sk_r_to_i.copy_from_slice(&sk_r_to_i_h);
    let mut transcript_hash = [0u8; 32];
    let th = Sha256::new()
        .chain_update(b"mt-noise-pq-v1-transcript")
        .chain_update(&transcript)
        .finalize();
    transcript_hash.copy_from_slice(&th);

    let session = NoisePqSession {
        sk_i_to_r,
        sk_r_to_i,
        transcript_hash,
    };

    // Extend transcript with rs_id_pk so msg3 signature binds to it.
    transcript.extend_from_slice(rs_id_pk.as_bytes());

    Ok(InitiatorMsg2Received {
        transcript,
        session,
        is_id_sk: state.is_id_sk,
        is_id_pk: state.is_id_pk,
    })
}

/// Initiator: send message 3 and finalize the session.
pub fn initiator_send_msg3(
    state: InitiatorMsg2Received,
) -> Result<(Vec<u8>, NoisePqSession), NoisePqError> {
    let InitiatorMsg2Received {
        mut transcript,
        session,
        is_id_sk,
        is_id_pk,
    } = state;
    transcript.extend_from_slice(is_id_pk.as_bytes());

    let sig_input = Sha256::new()
        .chain_update(SIG_DOMAIN_INITIATOR)
        .chain_update(&transcript)
        .finalize();
    let sig_input: [u8; 32] = sig_input.into();
    let sig_i = sign(&is_id_sk, &sig_input)?;

    let mut wire = Vec::with_capacity(NOISE_PQ_MSG3_SIZE);
    wire.extend_from_slice(is_id_pk.as_bytes());
    wire.extend_from_slice(sig_i.as_bytes());
    Ok((wire, session))
}

/// Responder-side state after receiving message 1.
pub struct ResponderMsg1Received {
    ke_pk: MlkemPublicKey,
    ke_pk_bytes: [u8; MLKEM_PUBLIC_KEY_SIZE],
    ct_rs_bytes: [u8; MLKEM_CIPHERTEXT_SIZE],
    ss_rs: [u8; 32],
    rs_id_sk: SecretKey,
    rs_id_pk: PublicKey,
}

/// Responder-side state after sending message 2.
pub struct ResponderMsg2Sent {
    transcript_through_msg2: Vec<u8>,
    session: NoisePqSession,
}

/// Responder: receive message 1.
pub fn responder_receive_msg1(
    msg1: &[u8],
    rs_static_sk: &MlkemSecretKey,
    rs_id_sk: SecretKey,
    rs_id_pk: PublicKey,
) -> Result<ResponderMsg1Received, NoisePqError> {
    if msg1.len() != NOISE_PQ_MSG1_SIZE {
        return Err(NoisePqError::BadMsgSize {
            expected: NOISE_PQ_MSG1_SIZE,
            actual: msg1.len(),
        });
    }
    let (ke_pk_slice, ct_rs_slice) = msg1.split_at(MLKEM_PUBLIC_KEY_SIZE);
    let ke_pk_arr: [u8; MLKEM_PUBLIC_KEY_SIZE] = ke_pk_slice
        .try_into()
        .map_err(|_| NoisePqError::InvalidPublicKey)?;
    let ke_pk = MlkemPublicKey::from_array(ke_pk_arr);
    let ct_rs = MlkemCiphertext::from_slice(ct_rs_slice).ok_or(NoisePqError::InvalidCiphertext)?;

    let ss_rs = mlkem_decapsulate(rs_static_sk, &ct_rs)?;
    let mut ss_rs_bytes = [0u8; 32];
    ss_rs_bytes.copy_from_slice(ss_rs.as_bytes());

    Ok(ResponderMsg1Received {
        ke_pk,
        ke_pk_bytes: ke_pk_arr,
        ct_rs_bytes: *ct_rs.as_bytes(),
        ss_rs: ss_rs_bytes,
        rs_id_sk,
        rs_id_pk,
    })
}

/// Responder: send message 2 (derives the session keys and signs the transcript).
pub fn responder_send_msg2(
    state: ResponderMsg1Received,
) -> Result<(Vec<u8>, ResponderMsg2Sent), NoisePqError> {
    let (ct_e, ss_e) = mlkem_encapsulate(&state.ke_pk)?;

    let mut transcript = Vec::with_capacity(NOISE_PQ_MSG1_SIZE + MLKEM_CIPHERTEXT_SIZE);
    transcript.extend_from_slice(&state.ke_pk_bytes);
    transcript.extend_from_slice(&state.ct_rs_bytes);
    transcript.extend_from_slice(ct_e.as_bytes());

    let transcript_for_sig = Sha256::new()
        .chain_update(SIG_DOMAIN_RESPONDER)
        .chain_update(&transcript)
        .finalize();
    let transcript_for_sig: [u8; 32] = transcript_for_sig.into();
    let sig_r = sign(&state.rs_id_sk, &transcript_for_sig)?;

    let mut wire = Vec::with_capacity(NOISE_PQ_MSG2_SIZE);
    wire.extend_from_slice(ct_e.as_bytes());
    wire.extend_from_slice(state.rs_id_pk.as_bytes());
    wire.extend_from_slice(sig_r.as_bytes());

    let mut master_input = Vec::with_capacity(32 + 32 + transcript.len() + PUBLIC_KEY_SIZE);
    master_input.extend_from_slice(&state.ss_rs);
    master_input.extend_from_slice(ss_e.as_bytes());
    master_input.extend_from_slice(&transcript);
    master_input.extend_from_slice(state.rs_id_pk.as_bytes());
    let master = Sha256::new()
        .chain_update(DOMAIN_MASTER)
        .chain_update(&master_input)
        .finalize();
    master_input.zeroize();
    let master_bytes: [u8; 32] = master.into();

    let sk_i_to_r_h = Sha256::new()
        .chain_update(DOMAIN_I2R)
        .chain_update(master_bytes)
        .finalize();
    let sk_r_to_i_h = Sha256::new()
        .chain_update(DOMAIN_R2I)
        .chain_update(master_bytes)
        .finalize();
    let mut sk_i_to_r = [0u8; 32];
    sk_i_to_r.copy_from_slice(&sk_i_to_r_h);
    let mut sk_r_to_i = [0u8; 32];
    sk_r_to_i.copy_from_slice(&sk_r_to_i_h);
    let mut transcript_hash = [0u8; 32];
    let th = Sha256::new()
        .chain_update(b"mt-noise-pq-v1-transcript")
        .chain_update(&transcript)
        .finalize();
    transcript_hash.copy_from_slice(&th);

    // Extend stored transcript so responder can verify msg3 by appending
    // is_id_pk and recomputing the signature input.
    transcript.extend_from_slice(state.rs_id_pk.as_bytes());

    let session = NoisePqSession {
        sk_i_to_r,
        sk_r_to_i,
        transcript_hash,
    };

    let saved = ResponderMsg2Sent {
        transcript_through_msg2: transcript,
        session,
    };
    Ok((wire, saved))
}

/// Responder: receive message 3, verify initiator's signature, return the
/// finalized session keys.
pub fn responder_receive_msg3(
    msg3: &[u8],
    state: ResponderMsg2Sent,
) -> Result<NoisePqSession, NoisePqError> {
    if msg3.len() != NOISE_PQ_MSG3_SIZE {
        return Err(NoisePqError::BadMsgSize {
            expected: NOISE_PQ_MSG3_SIZE,
            actual: msg3.len(),
        });
    }
    let (is_id_pk_slice, sig_i_slice) = msg3.split_at(PUBLIC_KEY_SIZE);
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

    let mut transcript = state.transcript_through_msg2;
    transcript.extend_from_slice(is_id_pk.as_bytes());
    let sig_input = Sha256::new()
        .chain_update(SIG_DOMAIN_INITIATOR)
        .chain_update(&transcript)
        .finalize();
    let sig_input: [u8; 32] = sig_input.into();
    if !verify(&is_id_pk, &sig_input, &sig_i) {
        return Err(NoisePqError::BadInitiatorSignature);
    }

    Ok(state.session)
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::{keypair_from_seed, keypair_from_seed_mlkem, KEYPAIR_SEED_SIZE};

    fn make_id(seed_byte: u8) -> (PublicKey, SecretKey) {
        let seed = [seed_byte; KEYPAIR_SEED_SIZE];
        keypair_from_seed(&seed).expect("test keygen")
    }

    fn make_kem_static() -> (MlkemPublicKey, MlkemSecretKey) {
        let seed = [0xAAu8; mt_crypto::MLKEM_SEED_SIZE];
        keypair_from_seed_mlkem(&seed).unwrap()
    }

    #[test]
    fn handshake_roundtrip() {
        let (rs_kem_pk, rs_kem_sk) = make_kem_static();
        let (rs_id_pk, rs_id_sk) = make_id(0x11);
        let (is_id_pk, is_id_sk) = make_id(0x22);

        let (msg1, init_state) = initiator_send_msg1(&rs_kem_pk, is_id_sk, is_id_pk).unwrap();
        assert_eq!(msg1.len(), NOISE_PQ_MSG1_SIZE);

        let resp_state = responder_receive_msg1(&msg1, &rs_kem_sk, rs_id_sk, rs_id_pk).unwrap();
        let (msg2, resp_after_msg2) = responder_send_msg2(resp_state).unwrap();
        assert_eq!(msg2.len(), NOISE_PQ_MSG2_SIZE);

        let init_after_msg2 = initiator_receive_msg2(&msg2, init_state).unwrap();
        let init_session_keys = (
            init_after_msg2.session.sk_i_to_r,
            init_after_msg2.session.sk_r_to_i,
            init_after_msg2.session.transcript_hash,
        );
        let (msg3, init_session) = initiator_send_msg3(init_after_msg2).unwrap();
        assert_eq!(msg3.len(), NOISE_PQ_MSG3_SIZE);
        let _ = init_session_keys;

        let resp_session = responder_receive_msg3(&msg3, resp_after_msg2).unwrap();

        assert_eq!(init_session.sk_i_to_r, resp_session.sk_i_to_r);
        assert_eq!(init_session.sk_r_to_i, resp_session.sk_r_to_i);
        assert_eq!(init_session.transcript_hash, resp_session.transcript_hash);
    }

    #[test]
    fn tamper_detection_msg2_signature() {
        let (rs_kem_pk, rs_kem_sk) = make_kem_static();
        let (rs_id_pk, rs_id_sk) = make_id(0x11);
        let (is_id_pk, is_id_sk) = make_id(0x22);

        let (msg1, init_state) = initiator_send_msg1(&rs_kem_pk, is_id_sk, is_id_pk).unwrap();
        let resp_state = responder_receive_msg1(&msg1, &rs_kem_sk, rs_id_sk, rs_id_pk).unwrap();
        let (mut msg2, _resp_after) = responder_send_msg2(resp_state).unwrap();
        // Flip a byte inside the responder's signature region.
        let sig_offset = MLKEM_CIPHERTEXT_SIZE + PUBLIC_KEY_SIZE;
        msg2[sig_offset] ^= 0x01;
        let r = initiator_receive_msg2(&msg2, init_state);
        assert_eq!(r.err(), Some(NoisePqError::BadResponderSignature));
    }

    #[test]
    fn tamper_detection_msg3_signature() {
        let (rs_kem_pk, rs_kem_sk) = make_kem_static();
        let (rs_id_pk, rs_id_sk) = make_id(0x11);
        let (is_id_pk, is_id_sk) = make_id(0x22);

        let (msg1, init_state) = initiator_send_msg1(&rs_kem_pk, is_id_sk, is_id_pk).unwrap();
        let resp_state = responder_receive_msg1(&msg1, &rs_kem_sk, rs_id_sk, rs_id_pk).unwrap();
        let (msg2, resp_after_msg2) = responder_send_msg2(resp_state).unwrap();
        let init_after_msg2 = initiator_receive_msg2(&msg2, init_state).unwrap();
        let (mut msg3, _init_session) = initiator_send_msg3(init_after_msg2).unwrap();
        msg3[PUBLIC_KEY_SIZE] ^= 0x01;
        let r = responder_receive_msg3(&msg3, resp_after_msg2);
        assert_eq!(r.err(), Some(NoisePqError::BadInitiatorSignature));
    }
}
