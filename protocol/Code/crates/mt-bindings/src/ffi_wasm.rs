//! WASM bindings — web client. Crypto on pure-Rust ml-dsa/ml-kem (OpenSSL does not
//! build into the browser). Byte-identity to native is guaranteed by FIPS 203/204 KAT:
//! account_id from the zero mnemonic == 9f199584…131a21 (see mt-bindings KAT).
#![cfg(all(target_arch = "wasm32", feature = "wasm"))]

use wasm_bindgen::prelude::*;

use ml_dsa::{
    EncodedVerifyingKey, Keypair, MlDsa65, Signature, Signer, SigningKey, Verifier, VerifyingKey,
    B32,
};
use mt_mnemonic::{mldsa_seed_for_role, mnemonic_to_master_seed};
use sha2::{Digest, Sha256};

const SUITE_MLDSA65_LE: [u8; 2] = [0x01, 0x00];

fn account_id_from_pk(pk: &[u8]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(mt_codec::domain::ACCOUNT);
    h.update([0u8]);
    h.update(SUITE_MLDSA65_LE);
    h.update(pk);
    h.finalize().into()
}

#[wasm_bindgen]
pub fn abi_version() -> u32 {
    super::ABI_VERSION
}

#[wasm_bindgen]
pub fn mnemonic_to_master_seed_js(mnemonic: &str) -> Result<Vec<u8>, JsValue> {
    mnemonic_to_master_seed(mnemonic)
        .map(|s| s.to_vec())
        .map_err(|e| JsValue::from_str(&format!("{e:?}")))
}

/// 24 words → pk(1952) ‖ acc_seed(32) ‖ account_id(32) = 2016 bytes.
/// acc_seed (ξ) — local secret; store on the device, sign via `sign`.
#[wasm_bindgen]
pub fn account_from_mnemonic(mnemonic: &str) -> Result<Vec<u8>, JsValue> {
    let master = mnemonic_to_master_seed(mnemonic)
        .map_err(|e| JsValue::from_str(&format!("mnemonic: {e:?}")))?;
    let acc_seed = mldsa_seed_for_role(&master, mt_codec::domain::ACCOUNT_KEY);
    let seed = B32::try_from(&acc_seed[..]).map_err(|_| JsValue::from_str("seed"))?;
    let sk = SigningKey::<MlDsa65>::from_seed(&seed);
    let pk = sk.verifying_key().encode();
    let account_id = account_id_from_pk(pk.as_slice());
    let mut out = Vec::with_capacity(1952 + 32 + 32);
    out.extend_from_slice(pk.as_slice());
    out.extend_from_slice(&acc_seed);
    out.extend_from_slice(&account_id);
    Ok(out)
}

/// 24 words -> app_kem_key (ML-KEM-768) via role "mt-app-encryption-key".
/// Returns: pk(1184) ‖ sk(2400). Byte-identical to native (OpenSSL) by cross-backend KAT.
#[wasm_bindgen]
pub fn app_kem_from_mnemonic(mnemonic: &str) -> Result<Vec<u8>, JsValue> {
    use ml_kem::{EncodedSizeUser, KemCore, MlKem768, B32 as KemB32};
    let master = mnemonic_to_master_seed(mnemonic)
        .map_err(|e| JsValue::from_str(&format!("mnemonic: {e:?}")))?;
    let seed = mt_mnemonic::mlkem_seed_for_role(&master, mt_codec::domain::APP_ENCRYPTION_KEY);
    let d = KemB32::try_from(&seed[..32]).map_err(|_| JsValue::from_str("d"))?;
    let z = KemB32::try_from(&seed[32..]).map_err(|_| JsValue::from_str("z"))?;
    let (dk, ek) = MlKem768::generate_deterministic(&d, &z);
    let mut out = Vec::with_capacity(1184 + 2400);
    out.extend_from_slice(ek.as_bytes().as_slice());
    out.extend_from_slice(dk.as_bytes().as_slice());
    Ok(out)
}

/// ML-KEM-768 KeyGen from a 64-byte seed (FIPS 203, deterministic). Returns pk(1184) ‖ sk(2400).
#[wasm_bindgen]
pub fn mlkem_keypair_from_seed(seed: &[u8]) -> Result<Vec<u8>, JsValue> {
    use ml_kem::{EncodedSizeUser, KemCore, MlKem768, B32 as KemB32};
    if seed.len() != 64 {
        return Err(JsValue::from_str("seed must be 64 bytes"));
    }
    let d = KemB32::try_from(&seed[..32]).map_err(|_| JsValue::from_str("d"))?;
    let z = KemB32::try_from(&seed[32..]).map_err(|_| JsValue::from_str("z"))?;
    let (dk, ek) = MlKem768::generate_deterministic(&d, &z);
    let mut out = Vec::with_capacity(1184 + 2400);
    out.extend_from_slice(ek.as_bytes().as_slice());
    out.extend_from_slice(dk.as_bytes().as_slice());
    Ok(out)
}

#[wasm_bindgen]
pub fn sign(acc_seed: &[u8], msg: &[u8]) -> Result<Vec<u8>, JsValue> {
    let seed =
        B32::try_from(acc_seed).map_err(|_| JsValue::from_str("acc_seed must be 32 bytes"))?;
    let sk = SigningKey::<MlDsa65>::from_seed(&seed);
    let sig: Signature<MlDsa65> = sk.sign(msg);
    Ok(sig.encode().as_slice().to_vec())
}

#[wasm_bindgen]
pub fn verify(pubkey: &[u8], msg: &[u8], sig: &[u8]) -> Result<bool, JsValue> {
    let enc = EncodedVerifyingKey::<MlDsa65>::try_from(pubkey)
        .map_err(|_| JsValue::from_str("bad pubkey"))?;
    let vk = VerifyingKey::<MlDsa65>::decode(&enc);
    let s = Signature::<MlDsa65>::try_from(sig).map_err(|_| JsValue::from_str("bad sig"))?;
    Ok(vk.verify(msg, &s).is_ok())
}

#[wasm_bindgen]
pub fn account_id_to_address(account_id: &[u8]) -> Result<String, JsValue> {
    let id: [u8; 32] = account_id
        .try_into()
        .map_err(|_| JsValue::from_str("account_id must be 32 bytes"))?;
    Ok(crate::account_id_to_address(&id))
}

// ── E2E engine (mt-messenger-e2e) for the web ──────────────────────────────
use mt_messenger_e2e::handshake::{
    build_handshake, process_handshake, RecipientBundle, RecipientKeys,
};
use mt_messenger_e2e::session::SessionState;

#[wasm_bindgen]
pub struct E2ePair {
    a: Vec<u8>,
    b: Vec<u8>,
}

#[wasm_bindgen]
impl E2ePair {
    #[wasm_bindgen(getter)]
    pub fn a(&self) -> Vec<u8> {
        self.a.clone()
    }
    #[wasm_bindgen(getter)]
    pub fn b(&self) -> Vec<u8> {
        self.b.clone()
    }
}

fn seed64(s: &[u8]) -> Result<[u8; 64], JsValue> {
    s.try_into()
        .map_err(|_| JsValue::from_str("seed must be 64 bytes"))
}
fn seed32(s: &[u8]) -> Result<[u8; 32], JsValue> {
    s.try_into()
        .map_err(|_| JsValue::from_str("seed must be 32 bytes"))
}

/// Alice: handshake + session. a = InitialHandshake, b = initiator session blob.
/// `opk_pub` is empty (len 0) — no one-time pre-key.
#[wasm_bindgen]
#[allow(clippy::too_many_arguments)]
pub fn e2e_build_handshake(
    alice_account_pub: &[u8],
    account_seed: &[u8],
    bob_account_pub: &[u8],
    bob_app_kem_pub: &[u8],
    bob_spk_pub: &[u8],
    spk_id: u32,
    opk_id: u32,
    opk_pub: &[u8],
    eph_seed: &[u8],
    send_time: u64,
) -> Result<E2ePair, JsValue> {
    let a_pub: [u8; 1952] = alice_account_pub
        .try_into()
        .map_err(|_| JsValue::from_str("a_pub"))?;
    let seed = seed32(account_seed)?;
    let b_pub: [u8; 1952] = bob_account_pub
        .try_into()
        .map_err(|_| JsValue::from_str("b_pub"))?;
    let app: [u8; 1184] = bob_app_kem_pub
        .try_into()
        .map_err(|_| JsValue::from_str("app"))?;
    let spk: [u8; 1184] = bob_spk_pub
        .try_into()
        .map_err(|_| JsValue::from_str("spk"))?;
    let opk: Option<[u8; 1184]> = if opk_pub.is_empty() {
        None
    } else {
        Some(opk_pub.try_into().map_err(|_| JsValue::from_str("opk"))?)
    };
    let eph = seed64(eph_seed)?;
    let bundle = RecipientBundle {
        account_key_pub: &b_pub,
        app_kem_pub: &app,
        signed_prekey_pub: &spk,
        spk_id,
        one_time: opk.as_ref().map(|p| (opk_id, p)),
    };
    let hs = build_handshake(&a_pub, &seed, &bundle, &eph, send_time)
        .map_err(|_| JsValue::from_str("handshake"))?;
    let session = SessionState::init_initiator(
        hs.transcript_hash,
        hs.session.root_key,
        hs.session.sending_chain_key,
        hs.eph_kem_pub_a,
        hs.eph_kem_sk_a,
        hs.signed_prekey_pub_b,
    );
    Ok(E2ePair {
        a: hs.bytes,
        b: session.to_bytes(),
    })
}

/// Bob: process handshake -> recipient session blob.
#[wasm_bindgen]
#[allow(clippy::too_many_arguments)]
pub fn e2e_process_handshake(
    hs: &[u8],
    bob_account_id: &[u8],
    bob_app_kem_pub: &[u8],
    bob_app_kem_sk: &[u8],
    bob_spk_pub: &[u8],
    bob_spk_sk: &[u8],
    opk_pub: &[u8],
    opk_sk: &[u8],
    now: u64,
    accept_skew: u64,
) -> Result<Vec<u8>, JsValue> {
    let acc_id: [u8; 32] = bob_account_id
        .try_into()
        .map_err(|_| JsValue::from_str("acc_id"))?;
    let app: [u8; 1184] = bob_app_kem_pub
        .try_into()
        .map_err(|_| JsValue::from_str("app"))?;
    let spk: [u8; 1184] = bob_spk_pub
        .try_into()
        .map_err(|_| JsValue::from_str("spk"))?;
    let opk: Option<([u8; 1184], &[u8])> = if opk_pub.is_empty() {
        None
    } else {
        Some((
            opk_pub.try_into().map_err(|_| JsValue::from_str("opk"))?,
            opk_sk,
        ))
    };
    let keys = RecipientKeys {
        account_id: &acc_id,
        app_kem_pub: &app,
        app_kem_sk: bob_app_kem_sk,
        signed_prekey_pub: &spk,
        signed_prekey_sk: bob_spk_sk,
        one_time: opk.as_ref().map(|(p, s)| (p, *s)),
    };
    let proc =
        process_handshake(hs, &keys, now, accept_skew).map_err(|_| JsValue::from_str("process"))?;
    let session = SessionState::init_responder(
        proc.transcript_hash,
        proc.session.root_key,
        proc.session.sending_chain_key,
        proc.eph_kem_pub_a,
        spk,
        bob_spk_sk.to_vec(),
    );
    Ok(session.to_bytes())
}

/// a = new session blob, b = message for the wire.
#[wasm_bindgen]
pub fn e2e_encrypt(session: &[u8], pt: &[u8], rng_seed: &[u8]) -> Result<E2ePair, JsValue> {
    let mut st = SessionState::from_bytes(session).map_err(|_| JsValue::from_str("session"))?;
    let seed = seed64(rng_seed)?;
    let msg = st
        .encrypt(pt, &seed)
        .map_err(|_| JsValue::from_str("encrypt"))?;
    Ok(E2ePair {
        a: st.to_bytes(),
        b: msg,
    })
}

/// a = new session blob, b = plaintext.
#[wasm_bindgen]
pub fn e2e_decrypt(session: &[u8], msg: &[u8]) -> Result<E2ePair, JsValue> {
    let mut st = SessionState::from_bytes(session).map_err(|_| JsValue::from_str("session"))?;
    let pt = st.decrypt(msg).map_err(|_| JsValue::from_str("decrypt"))?;
    Ok(E2ePair {
        a: st.to_bytes(),
        b: pt,
    })
}
