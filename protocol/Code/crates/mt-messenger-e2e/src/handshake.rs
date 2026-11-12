//! Stage 5 — PQXDH state machine: build/parse InitialHandshake, Alice's side
//! (build) and Bob's side (process). Transcript and layout are byte-exact per spec.
//! Crypto goes through crate::crypto (native/wasm cfg split), bytes only.

use sha2::{Digest, Sha256};

use crate::crypto::{
    dsa_sign, dsa_verify, kem_decapsulate, kem_encapsulate, kem_keypair_from_seed, MLDSA_PUB,
    MLDSA_SIG, MLKEM_CT, MLKEM_PUB,
};
use crate::pqxdh::{confirm_tag, derive_session_keys, SessionKeys, DOMAIN_SIG};

pub const MLDSA_PUBKEY: usize = MLDSA_PUB;
pub const MLKEM_PUBKEY: usize = MLKEM_PUB;
const SUITE_MLDSA65_LE: [u8; 2] = [0x01, 0x00];

#[derive(Debug, PartialEq, Eq)]
pub enum E2eError {
    BadLength,
    BadVersion,
    BadOpkFlag,
    Stale,
    BadSignature,
    ConfirmMismatch,
    Crypto,
}

pub fn account_id(account_key_pub: &[u8]) -> [u8; 32] {
    // account_id per the spec formula — via canonical mt_crypto::hash (same code as mt_state::derive_account_id).
    mt_crypto::hash(
        mt_codec::domain::ACCOUNT,
        &[&SUITE_MLDSA65_LE, account_key_pub],
    )
}

/// Bob's bundle (public part, from Stage 4).
pub struct RecipientBundle<'a> {
    pub account_key_pub: &'a [u8; MLDSA_PUB],
    pub app_kem_pub: &'a [u8; MLKEM_PUB],
    pub signed_prekey_pub: &'a [u8; MLKEM_PUB],
    pub spk_id: u32,
    pub one_time: Option<(u32, &'a [u8; MLKEM_PUB])>,
}

#[allow(clippy::too_many_arguments)]
fn transcript_bytes(
    account_id_a: &[u8; 32],
    account_id_b: &[u8; 32],
    send_time: u64,
    eph_kem_pub_a: &[u8; MLKEM_PUB],
    app_kem_pub_b: &[u8; MLKEM_PUB],
    signed_prekey_pub_b: &[u8; MLKEM_PUB],
    spk_id_b: u32,
    opk: Option<(u32, &[u8; MLKEM_PUB])>,
    ct_id: &[u8; MLKEM_CT],
    ct_spk: &[u8; MLKEM_CT],
    ct_opk: Option<&[u8; MLKEM_CT]>,
) -> Vec<u8> {
    let mut t = Vec::new();
    t.extend_from_slice(b"mt-pqxdh-v1");
    t.push(0u8);
    t.extend_from_slice(account_id_a);
    t.extend_from_slice(account_id_b);
    t.extend_from_slice(&send_time.to_le_bytes());
    t.extend_from_slice(eph_kem_pub_a);
    t.extend_from_slice(app_kem_pub_b);
    t.extend_from_slice(signed_prekey_pub_b);
    t.extend_from_slice(&spk_id_b.to_le_bytes());
    match opk {
        Some((opk_id, opk_pub)) => {
            t.push(0x01);
            t.extend_from_slice(opk_pub);
            t.extend_from_slice(&opk_id.to_le_bytes());
        },
        None => t.push(0x00),
    }
    t.extend_from_slice(ct_id);
    t.extend_from_slice(ct_spk);
    if let Some(c) = ct_opk {
        t.extend_from_slice(c);
    }
    t
}

pub struct Handshake {
    pub bytes: Vec<u8>,
    pub session: SessionKeys,
    pub eph_kem_pub_a: [u8; MLKEM_PUB],
    pub eph_kem_sk_a: Vec<u8>,
    pub signed_prekey_pub_b: [u8; MLKEM_PUB],
    pub transcript_hash: [u8; 32],
}

/// Alice's side. `account_seed` (32B) is the seed of her ML-DSA key; `eph_seed` (64B) is
/// client randomness for the ephemeral ML-KEM pair.
pub fn build_handshake(
    alice_account_pub: &[u8; MLDSA_PUB],
    account_seed: &[u8; 32],
    bob: &RecipientBundle,
    eph_seed: &[u8; 64],
    send_time: u64,
) -> Result<Handshake, E2eError> {
    let (eph_pub, eph_sk) = kem_keypair_from_seed(eph_seed).ok_or(E2eError::Crypto)?;
    let (ct_id, ss_id) = kem_encapsulate(bob.app_kem_pub).ok_or(E2eError::Crypto)?;
    let (ct_spk, ss_spk) = kem_encapsulate(bob.signed_prekey_pub).ok_or(E2eError::Crypto)?;
    let opk_enc = match bob.one_time {
        Some((id, pk)) => {
            let (ct, ss) = kem_encapsulate(pk).ok_or(E2eError::Crypto)?;
            Some((id, ct, ss))
        },
        None => None,
    };

    let id_a = account_id(alice_account_pub);
    let id_b = account_id(bob.account_key_pub);
    let opk_pub_ref = bob.one_time;
    let ct_opk_ref = opk_enc.as_ref().map(|(_, ct, _)| ct);

    let tb = transcript_bytes(
        &id_a,
        &id_b,
        send_time,
        &eph_pub,
        bob.app_kem_pub,
        bob.signed_prekey_pub,
        bob.spk_id,
        opk_pub_ref,
        &ct_id,
        &ct_spk,
        ct_opk_ref,
    );
    let transcript_hash: [u8; 32] = Sha256::digest(&tb).into();

    let mut sig_msg = DOMAIN_SIG.to_vec();
    sig_msg.push(0u8);
    sig_msg.extend_from_slice(&transcript_hash);
    let sig = dsa_sign(account_seed, &sig_msg).ok_or(E2eError::Crypto)?;

    let ss_opk_ref = opk_enc.as_ref().map(|(_, _, ss)| *ss);
    let session = derive_session_keys(&ss_id, &ss_spk, ss_opk_ref.as_ref(), &transcript_hash);
    let tag = confirm_tag(&session.confirm_key, &transcript_hash);

    let mut out = Vec::new();
    out.push(0x01);
    out.extend_from_slice(alice_account_pub);
    out.extend_from_slice(&eph_pub);
    out.extend_from_slice(&send_time.to_le_bytes());
    out.extend_from_slice(&bob.spk_id.to_le_bytes());
    match (bob.one_time, &opk_enc) {
        (Some((opk_id, _)), Some((_, ct_opk, _))) => {
            out.push(0x01);
            out.extend_from_slice(&opk_id.to_le_bytes());
            out.extend_from_slice(&ct_id);
            out.extend_from_slice(&ct_spk);
            out.extend_from_slice(ct_opk);
        },
        _ => {
            out.push(0x00);
            out.extend_from_slice(&ct_id);
            out.extend_from_slice(&ct_spk);
        },
    }
    out.extend_from_slice(&sig);
    out.extend_from_slice(&tag);

    Ok(Handshake {
        bytes: out,
        session,
        eph_kem_pub_a: eph_pub,
        eph_kem_sk_a: eph_sk,
        signed_prekey_pub_b: *bob.signed_prekey_pub,
        transcript_hash,
    })
}

pub struct Processed {
    pub session: SessionKeys,
    pub eph_kem_pub_a: [u8; MLKEM_PUB],
    pub transcript_hash: [u8; 32],
    pub opk_consumed: Option<u32>,
}

/// Bob's private material.
pub struct RecipientKeys<'a> {
    pub account_id: &'a [u8; 32],
    pub app_kem_pub: &'a [u8; MLKEM_PUB],
    pub app_kem_sk: &'a [u8],
    pub signed_prekey_pub: &'a [u8; MLKEM_PUB],
    pub signed_prekey_sk: &'a [u8],
    pub one_time: Option<(&'a [u8; MLKEM_PUB], &'a [u8])>,
}

fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut d = 0u8;
    for i in 0..a.len() {
        d |= a[i] ^ b[i];
    }
    d == 0
}

/// Bob's side: parse, freshness, sig_A verification, three decapsulations, root derivation,
/// confirm_tag check. Any failure → rejection without state change.
pub fn process_handshake(
    hs: &[u8],
    bob: &RecipientKeys,
    now: u64,
    accept_skew: u64,
) -> Result<Processed, E2eError> {
    let base = 1 + MLDSA_PUB + MLKEM_PUB + 8 + 4;
    if hs.len() < base + 1 {
        return Err(E2eError::BadLength);
    }
    if hs[0] != 0x01 {
        return Err(E2eError::BadVersion);
    }
    let mut p = 1;
    let account_key_pub_a = &hs[p..p + MLDSA_PUB];
    p += MLDSA_PUB;
    let eph_kem_pub_a = &hs[p..p + MLKEM_PUB];
    p += MLKEM_PUB;
    let send_time = u64::from_le_bytes(hs[p..p + 8].try_into().unwrap());
    p += 8;
    let spk_id_b = u32::from_le_bytes(hs[p..p + 4].try_into().unwrap());
    p += 4;
    let opk_flag = hs[p];
    p += 1;
    if opk_flag != 0x00 && opk_flag != 0x01 {
        return Err(E2eError::BadOpkFlag);
    }
    let has_opk = opk_flag == 0x01;
    if now.abs_diff(send_time) > accept_skew {
        return Err(E2eError::Stale);
    }
    let expect = base
        + 1
        + if has_opk {
            4 + 3 * MLKEM_CT
        } else {
            2 * MLKEM_CT
        }
        + MLDSA_SIG
        + 32;
    if hs.len() != expect {
        return Err(E2eError::BadLength);
    }
    if has_opk && bob.one_time.is_none() {
        return Err(E2eError::BadOpkFlag);
    }
    let opk_id_b = if has_opk {
        let v = u32::from_le_bytes(hs[p..p + 4].try_into().unwrap());
        p += 4;
        Some(v)
    } else {
        None
    };
    let ct_id = &hs[p..p + MLKEM_CT];
    p += MLKEM_CT;
    let ct_spk = &hs[p..p + MLKEM_CT];
    p += MLKEM_CT;
    let ct_opk = if has_opk {
        let c = &hs[p..p + MLKEM_CT];
        p += MLKEM_CT;
        Some(c)
    } else {
        None
    };
    let sig = &hs[p..p + MLDSA_SIG];
    p += MLDSA_SIG;
    let tag = &hs[p..p + 32];

    let id_a = account_id(account_key_pub_a);
    let eph_arr: [u8; MLKEM_PUB] = eph_kem_pub_a.try_into().unwrap();
    let opk_for_transcript = match (has_opk, opk_id_b, bob.one_time) {
        (true, Some(id), Some((pk, _))) => Some((id, pk)),
        _ => None,
    };

    let tb = transcript_bytes(
        &id_a,
        bob.account_id,
        send_time,
        &eph_arr,
        bob.app_kem_pub,
        bob.signed_prekey_pub,
        spk_id_b,
        opk_for_transcript,
        ct_id.try_into().unwrap(),
        ct_spk.try_into().unwrap(),
        ct_opk.map(|c| <&[u8; MLKEM_CT]>::try_from(c).unwrap()),
    );
    let transcript_hash: [u8; 32] = Sha256::digest(&tb).into();

    let mut sig_msg = DOMAIN_SIG.to_vec();
    sig_msg.push(0u8);
    sig_msg.extend_from_slice(&transcript_hash);
    if !dsa_verify(account_key_pub_a, &sig_msg, sig) {
        return Err(E2eError::BadSignature);
    }

    let ss_id = kem_decapsulate(bob.app_kem_sk, ct_id).ok_or(E2eError::Crypto)?;
    let ss_spk = kem_decapsulate(bob.signed_prekey_sk, ct_spk).ok_or(E2eError::Crypto)?;
    let ss_opk = match (ct_opk, bob.one_time) {
        (Some(c), Some((_, sk))) => Some(kem_decapsulate(sk, c).ok_or(E2eError::Crypto)?),
        _ => None,
    };

    let session = derive_session_keys(&ss_id, &ss_spk, ss_opk.as_ref(), &transcript_hash);
    let expected_tag = confirm_tag(&session.confirm_key, &transcript_hash);
    if !ct_eq(&expected_tag, tag) {
        return Err(E2eError::ConfirmMismatch);
    }

    Ok(Processed {
        session,
        eph_kem_pub_a: eph_arr,
        transcript_hash,
        opk_consumed: opk_id_b,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn acc(seed: &[u8; 32]) -> [u8; MLDSA_PUB] {
        crate::crypto::dsa_pub_from_seed(seed).unwrap()
    }
    fn kem(seed: u8) -> ([u8; MLKEM_PUB], Vec<u8>) {
        kem_keypair_from_seed(&[seed; 64]).unwrap()
    }

    #[test]
    fn handshake_agreement_with_opk() {
        let (app_pub, app_sk) = kem(0x11);
        let (spk_pub, spk_sk) = kem(0x22);
        let (opk_pub, opk_sk) = kem(0x33);
        let bob_pub = acc(&[0x44; 32]);
        let bob_id = account_id(&bob_pub);
        let alice_pub = acc(&[0x55; 32]);

        let bundle = RecipientBundle {
            account_key_pub: &bob_pub,
            app_kem_pub: &app_pub,
            signed_prekey_pub: &spk_pub,
            spk_id: 7,
            one_time: Some((99, &opk_pub)),
        };
        let hs = build_handshake(&alice_pub, &[0x55; 32], &bundle, &[0x66; 64], 1000).unwrap();
        let keys = RecipientKeys {
            account_id: &bob_id,
            app_kem_pub: &app_pub,
            app_kem_sk: &app_sk,
            signed_prekey_pub: &spk_pub,
            signed_prekey_sk: &spk_sk,
            one_time: Some((&opk_pub, &opk_sk)),
        };
        let proc = process_handshake(&hs.bytes, &keys, 1001, 604800).unwrap();
        assert_eq!(hs.session.root_key, proc.session.root_key);
        assert_eq!(hs.transcript_hash, proc.transcript_hash);
        assert_eq!(proc.opk_consumed, Some(99));
    }

    #[test]
    fn tampered_confirm_tag_rejected() {
        let (app_pub, app_sk) = kem(0x11);
        let (spk_pub, spk_sk) = kem(0x22);
        let bob_pub = acc(&[0x44; 32]);
        let bob_id = account_id(&bob_pub);
        let alice_pub = acc(&[0x55; 32]);
        let bundle = RecipientBundle {
            account_key_pub: &bob_pub,
            app_kem_pub: &app_pub,
            signed_prekey_pub: &spk_pub,
            spk_id: 7,
            one_time: None,
        };
        let mut hs = build_handshake(&alice_pub, &[0x55; 32], &bundle, &[0x66; 64], 1000).unwrap();
        let n = hs.bytes.len();
        hs.bytes[n - 1] ^= 1;
        let keys = RecipientKeys {
            account_id: &bob_id,
            app_kem_pub: &app_pub,
            app_kem_sk: &app_sk,
            signed_prekey_pub: &spk_pub,
            signed_prekey_sk: &spk_sk,
            one_time: None,
        };
        assert!(matches!(
            process_handshake(&hs.bytes, &keys, 1001, 604800),
            Err(E2eError::ConfirmMismatch)
        ));
    }

    #[test]
    fn stale_rejected() {
        let (app_pub, app_sk) = kem(0x11);
        let (spk_pub, spk_sk) = kem(0x22);
        let bob_pub = acc(&[0x44; 32]);
        let bob_id = account_id(&bob_pub);
        let alice_pub = acc(&[0x55; 32]);
        let bundle = RecipientBundle {
            account_key_pub: &bob_pub,
            app_kem_pub: &app_pub,
            signed_prekey_pub: &spk_pub,
            spk_id: 7,
            one_time: None,
        };
        let hs = build_handshake(&alice_pub, &[0x55; 32], &bundle, &[0x66; 64], 1000).unwrap();
        let keys = RecipientKeys {
            account_id: &bob_id,
            app_kem_pub: &app_pub,
            app_kem_sk: &app_sk,
            signed_prekey_pub: &spk_pub,
            signed_prekey_sk: &spk_sk,
            one_time: None,
        };
        assert!(matches!(
            process_handshake(&hs.bytes, &keys, 1_000_000, 604800),
            Err(E2eError::Stale)
        ));
    }
}
