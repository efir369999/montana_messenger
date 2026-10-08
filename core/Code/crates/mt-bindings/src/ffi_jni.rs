//! JNI surface for Android Kotlin.
//!
//! Re-exports the same functions as ffi_c.rs, but through the JNI ABI with correct
//! Java_<pkg>_<class>_<method> names. Class on the Kotlin side: `quest.montana.app.MtBindings`.
//!
//! Build: `cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -p mt-bindings build --release`.
//! Artifact: `libmt_bindings.so` (3 ABI) → `Android/MontanaApp/app/src/main/jniLibs/{abi}/`.

#![cfg(target_os = "android")]

use jni::objects::{JByteArray, JClass, JString};
use jni::sys::{jbyteArray, jint, jlong};
use jni::JNIEnv;

use mt_codec::domain;
use mt_crypto::{
    keypair_from_seed, keypair_from_seed_mlkem, sign as mldsa_sign, verify as mldsa_verify,
    PublicKey, SecretKey, Signature,
};
use mt_mnemonic::{
    entropy_to_mnemonic, hkdf_expand, hmac_sha256, mldsa_seed_for_role, mlkem_seed_for_role,
    mnemonic_to_entropy, mnemonic_to_master_seed,
};
use mt_state::derive_account_id;
use zeroize::Zeroizing;

use super::{account_id_to_address, address_to_account_id};
use mt_messenger_e2e::handshake::{
    build_handshake, process_handshake, RecipientBundle, RecipientKeys,
};
use mt_messenger_e2e::media::{
    blob_id as media_blob_id, open_blob, pad_len as media_pad_len, seal_blob,
};
use mt_messenger_e2e::session::SessionState;

const MLKEM_PUB: usize = super::MT_MLKEM_PUBKEY_SIZE;
const MLKEM_SK: usize = super::MT_MLKEM_SECKEY_SIZE;
const MLDSA_PUB: usize = super::MT_MLDSA_PUBKEY_SIZE;

// Multi-output JNI: [4B BE len(a)] a b  → Kotlin splits by prefix. Freed by the JVM GC.
fn cat_lp(a: &[u8], b: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(4 + a.len() + b.len());
    v.extend_from_slice(&(a.len() as u32).to_be_bytes());
    v.extend_from_slice(a);
    v.extend_from_slice(b);
    v
}

const MT_SUITE_MLDSA65: u16 = 0x0001;

/// Matches the error codes from ffi_c.rs (negative).
/// On the Kotlin side treated as throw IllegalArgumentException/IllegalStateException.

#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeAbiVersion(
    _env: JNIEnv,
    _class: JClass,
) -> jint {
    super::ABI_VERSION as jint
}

/// 24 words → 64-byte master_seed. Returns byte[64] or null on error.
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMnemonicToMasterSeed<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    mnemonic_jstr: JString<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let mnemonic: String = match env.get_string(&mnemonic_jstr) {
        Ok(s) => s.into(),
        Err(_) => return null,
    };
    let seed = match mnemonic_to_master_seed(&mnemonic) {
        Ok(s) => s,
        Err(_) => return null,
    };
    match env.byte_array_from_slice(&seed) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// Fresh identity: health-tested OS entropy → 24-word UTF-8 mnemonic. Returns
/// null when the source is unavailable or its output fails the health tests.
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeGenerateMnemonic<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
) -> jni::sys::jstring {
    let null = std::ptr::null_mut();
    let mnemonic = match mt_mnemonic::generate_mnemonic() {
        Ok(m) => m,
        Err(_) => return null,
    };
    match env.new_string(mnemonic.as_str()) {
        Ok(s) => s.into_raw(),
        Err(_) => null,
    }
}

/// 32 bytes entropy → 24-word UTF-8 mnemonic.
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeEntropyToMnemonic<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    entropy: JByteArray<'local>,
) -> jni::sys::jstring {
    let null = std::ptr::null_mut();
    let bytes = match env.convert_byte_array(entropy) {
        Ok(b) if b.len() == 32 => b,
        _ => return null,
    };
    let mut arr = Zeroizing::new([0u8; 32]);
    arr.copy_from_slice(&bytes);
    if mt_mnemonic::health_check(&arr[..]).is_err() {
        return null;
    }
    let mnemonic = Zeroizing::new(entropy_to_mnemonic(&arr));
    match env.new_string(mnemonic.as_str()) {
        Ok(s) => s.into_raw(),
        Err(_) => null,
    }
}

/// 24 words → ML-DSA-65 account: byte[1952 + 4032 + 32] = pk||sk||account_id.
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeAccountFromMnemonic<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    mnemonic_jstr: JString<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let mnemonic: String = match env.get_string(&mnemonic_jstr) {
        Ok(s) => s.into(),
        Err(_) => return null,
    };
    let master = Zeroizing::new(match mnemonic_to_master_seed(&mnemonic) {
        Ok(s) => s,
        Err(_) => return null,
    });
    let acc_seed = Zeroizing::new(mldsa_seed_for_role(&master, domain::ACCOUNT_KEY));
    let (pk, sk) = match keypair_from_seed(&acc_seed) {
        Ok(kp) => kp,
        Err(_) => return null,
    };
    let account_id = derive_account_id(MT_SUITE_MLDSA65, pk.as_bytes());

    let mut buf = Vec::with_capacity(
        super::MT_MLDSA_PUBKEY_SIZE + super::MT_MLDSA_SECKEY_SIZE + super::MT_ACCOUNT_ID_LEN,
    );
    buf.extend_from_slice(pk.as_bytes());
    buf.extend_from_slice(sk.as_bytes());
    buf.extend_from_slice(&account_id);

    let out = env.byte_array_from_slice(&buf);
    for b in buf.iter_mut() {
        *b = 0;
    }
    match out {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// ML-DSA-65 sign(seckey[4032], msg) → signature[3309] (or null on error).
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeSign<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    seckey: JByteArray<'local>,
    msg: JByteArray<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let mut sk_bytes = match env.convert_byte_array(seckey) {
        Ok(b) => b,
        Err(_) => return null,
    };
    let m = match env.convert_byte_array(msg) {
        Ok(b) => b,
        Err(_) => return null,
    };
    let sk = match SecretKey::from_slice(&sk_bytes) {
        Some(k) => k,
        None => return null,
    };
    let sig = match mldsa_sign(&sk, &m) {
        Ok(s) => s,
        Err(_) => {
            for b in sk_bytes.iter_mut() {
                *b = 0;
            }
            return null;
        },
    };
    for b in sk_bytes.iter_mut() {
        *b = 0;
    }
    match env.byte_array_from_slice(sig.as_bytes()) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// ML-DSA-65 verify. Returns 1 (valid) / 0 (invalid) / -1 (input error).
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeVerify<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    pubkey: JByteArray<'local>,
    msg: JByteArray<'local>,
    sig: JByteArray<'local>,
) -> jint {
    let pk_bytes = match env.convert_byte_array(pubkey) {
        Ok(b) => b,
        Err(_) => return -1,
    };
    let m = match env.convert_byte_array(msg) {
        Ok(b) => b,
        Err(_) => return -1,
    };
    let sig_bytes = match env.convert_byte_array(sig) {
        Ok(b) => b,
        Err(_) => return -1,
    };
    let pk = match PublicKey::from_slice(&pk_bytes) {
        Some(k) => k,
        None => return -1,
    };
    let signature = match Signature::from_slice(&sig_bytes) {
        Some(s) => s,
        None => return -1,
    };
    if mldsa_verify(&pk, &m, &signature) {
        1
    } else {
        0
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Full crypto surface SSOT (mirror of ffi_c.rs) — identity/address/KEM.
// ─────────────────────────────────────────────────────────────────────────────

/// 24 words → 32-byte ML-DSA account seed (for E2E build_handshake, role ACCOUNT_KEY).
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeAccountSeedFromMnemonic<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    mnemonic_jstr: JString<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let mnemonic: String = match env.get_string(&mnemonic_jstr) {
        Ok(s) => s.into(),
        Err(_) => return null,
    };
    let master = Zeroizing::new(match mnemonic_to_master_seed(&mnemonic) {
        Ok(s) => s,
        Err(_) => return null,
    });
    let seed = Zeroizing::new(mldsa_seed_for_role(&master, domain::ACCOUNT_KEY));
    let out = env.byte_array_from_slice(&seed[..]);
    match out {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// 24 words → 32 bytes entropy (for history_key).
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMnemonicToEntropy<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    mnemonic_jstr: JString<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let mnemonic: String = match env.get_string(&mnemonic_jstr) {
        Ok(s) => s.into(),
        Err(_) => return null,
    };
    let ent = match mnemonic_to_entropy(&mnemonic) {
        Ok(e) => e,
        Err(_) => return null,
    };
    match env.byte_array_from_slice(&ent) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// 24 words → app_kem (ML-KEM-768): pub[1184] ‖ sk[2400].
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeAppKemFromMnemonic<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    mnemonic_jstr: JString<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let mnemonic: String = match env.get_string(&mnemonic_jstr) {
        Ok(s) => s.into(),
        Err(_) => return null,
    };
    let master = Zeroizing::new(match mnemonic_to_master_seed(&mnemonic) {
        Ok(s) => s,
        Err(_) => return null,
    });
    let kem_seed = Zeroizing::new(mlkem_seed_for_role(&master, domain::APP_ENCRYPTION_KEY));
    let (pk, sk) = match keypair_from_seed_mlkem(&kem_seed) {
        Ok(kp) => kp,
        Err(_) => return null,
    };
    let mut buf = Vec::with_capacity(super::MT_MLKEM_PUBKEY_SIZE + super::MT_MLKEM_SECKEY_SIZE);
    buf.extend_from_slice(pk.as_bytes());
    buf.extend_from_slice(sk.as_bytes());
    let out = env.byte_array_from_slice(&buf);
    for b in buf.iter_mut() {
        *b = 0;
    }
    match out {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// ML-KEM-768 KeyGen from a 64-byte seed → pub[1184] ‖ sk[2400] (for SPK/OTK).
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMlkemKeypairFromSeed<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    seed: JByteArray<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let seed_bytes = match env.convert_byte_array(seed) {
        Ok(b) => b,
        Err(_) => return null,
    };
    if seed_bytes.len() != super::MT_MLKEM_SEED_LEN {
        return null;
    }
    let mut arr = Zeroizing::new([0u8; super::MT_MLKEM_SEED_LEN]);
    arr.copy_from_slice(&seed_bytes);
    let (pk, sk) = match keypair_from_seed_mlkem(&arr) {
        Ok(kp) => kp,
        Err(_) => return null,
    };
    let mut buf = Vec::with_capacity(super::MT_MLKEM_PUBKEY_SIZE + super::MT_MLKEM_SECKEY_SIZE);
    buf.extend_from_slice(pk.as_bytes());
    buf.extend_from_slice(sk.as_bytes());
    let out = env.byte_array_from_slice(&buf);
    for b in buf.iter_mut() {
        *b = 0;
    }
    match out {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// account_id[32] → address "mt…" (Base58Check) as UTF-8 byte[].
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeAccountIdToAddress<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    account_id: JByteArray<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let id_bytes = match env.convert_byte_array(account_id) {
        Ok(b) => b,
        Err(_) => return null,
    };
    if id_bytes.len() != super::MT_ACCOUNT_ID_LEN {
        return null;
    }
    let mut id = [0u8; super::MT_ACCOUNT_ID_LEN];
    id.copy_from_slice(&id_bytes);
    let addr = account_id_to_address(&id);
    match env.byte_array_from_slice(addr.as_bytes()) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// address "mt…" → account_id[32] (verifies the checksum; null if invalid).
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeAddressToAccountId<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    address_jstr: JString<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let address: String = match env.get_string(&address_jstr) {
        Ok(s) => s.into(),
        Err(_) => return null,
    };
    match address_to_account_id(&address) {
        Some(id) => match env.byte_array_from_slice(&id) {
            Ok(arr) => arr.into_raw(),
            Err(_) => null,
        },
        None => null,
    }
}

/// history_key = HKDF-SHA256(0×32, entropy_32, "mt-history-key", 32) → byte[32]. SSOT.
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeHistoryKey<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    entropy: JByteArray<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let ent = match env.convert_byte_array(entropy) {
        Ok(b) => b,
        Err(_) => return null,
    };
    if ent.len() != super::MT_HISTORY_KEY_LEN {
        return null;
    }
    let prk = hmac_sha256(&[0u8; 32], &ent);
    let okm = hkdf_expand(&prk, domain::MSG_HISTORY_KEY, super::MT_HISTORY_KEY_LEN);
    match env.byte_array_from_slice(&okm) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// media_key = HKDF-SHA256(0×32, entropy_32, "mt-media-key", 32) → byte[32]. SSOT (≠ history_key).
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMediaKey<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    entropy: JByteArray<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let ent = match env.convert_byte_array(entropy) {
        Ok(b) => b,
        Err(_) => return null,
    };
    if ent.len() != super::MT_HISTORY_KEY_LEN {
        return null;
    }
    let prk = hmac_sha256(&[0u8; 32], &ent);
    let okm = hkdf_expand(&prk, domain::MSG_MEDIA_KEY, super::MT_HISTORY_KEY_LEN);
    match env.byte_array_from_slice(&okm) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  E2E engine (KEM ratchet) — mirror of ffi_e2e.rs. Multi-output via cat_lp.
// ─────────────────────────────────────────────────────────────────────────────

/// RatchetEncrypt: session ⊕ plaintext ⊕ rng_seed[64] → [len(newSession)] newSession ‖ msg.
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeE2eEncrypt<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    session: JByteArray<'local>,
    pt: JByteArray<'local>,
    rng_seed: JByteArray<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let sess = match env.convert_byte_array(session) {
        Ok(b) => b,
        Err(_) => return null,
    };
    let plaintext = match env.convert_byte_array(pt) {
        Ok(b) => b,
        Err(_) => return null,
    };
    let seed_v = match env.convert_byte_array(rng_seed) {
        Ok(b) => b,
        Err(_) => return null,
    };
    if seed_v.len() != 64 {
        return null;
    }
    let mut st = match SessionState::from_bytes(&sess) {
        Ok(s) => s,
        Err(_) => return null,
    };
    // length 64 checked above — try_into does not panic
    let seed: [u8; 64] = seed_v.as_slice().try_into().unwrap();
    let msg = match st.encrypt(&plaintext, &seed) {
        Ok(m) => m,
        Err(_) => return null,
    };
    let out = cat_lp(&st.to_bytes(), &msg);
    match env.byte_array_from_slice(&out) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// RatchetDecrypt: session ⊕ msg → [len(newSession)] newSession ‖ plaintext.
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeE2eDecrypt<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    session: JByteArray<'local>,
    msg: JByteArray<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let sess = match env.convert_byte_array(session) {
        Ok(b) => b,
        Err(_) => return null,
    };
    let message = match env.convert_byte_array(msg) {
        Ok(b) => b,
        Err(_) => return null,
    };
    let mut st = match SessionState::from_bytes(&sess) {
        Ok(s) => s,
        Err(_) => return null,
    };
    let pt = match st.decrypt(&message) {
        Ok(p) => p,
        Err(_) => return null,
    };
    let out = cat_lp(&st.to_bytes(), &pt);
    match env.byte_array_from_slice(&out) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// Alice: build_handshake + init_initiator → [len(hs)] hs ‖ session.
/// Arguments: alice_account_pub, account_seed[32], bob_account_pub, bob_app_kem_pub,
/// bob_spk_pub, spk_id, opk_id (0=none), bob_opk_pub (empty if none), eph_seed[64], send_time.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeE2eBuildHandshake<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    alice_account_pub: JByteArray<'local>,
    account_seed: JByteArray<'local>,
    bob_account_pub: JByteArray<'local>,
    bob_app_kem_pub: JByteArray<'local>,
    bob_spk_pub: JByteArray<'local>,
    spk_id: jint,
    opk_id: jint,
    bob_opk_pub: JByteArray<'local>,
    eph_seed: JByteArray<'local>,
    send_time: jlong,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    macro_rules! ba {
        ($x:expr) => {
            match env.convert_byte_array($x) {
                Ok(b) => b,
                Err(_) => return null,
            }
        };
    }
    let a_pub_v = ba!(alice_account_pub);
    let seed_v = ba!(account_seed);
    let b_pub_v = ba!(bob_account_pub);
    let app_pub_v = ba!(bob_app_kem_pub);
    let spk_pub_v = ba!(bob_spk_pub);
    let opk_pub_v = ba!(bob_opk_pub);
    let eph_v = ba!(eph_seed);
    if a_pub_v.len() != MLDSA_PUB
        || seed_v.len() != 32
        || b_pub_v.len() != MLDSA_PUB
        || app_pub_v.len() != MLKEM_PUB
        || spk_pub_v.len() != MLKEM_PUB
        || eph_v.len() != 64
    {
        return null;
    }
    // all lengths checked above (return null otherwise) — try_into does not panic
    let a_pub: [u8; MLDSA_PUB] = a_pub_v.as_slice().try_into().unwrap();
    let seed: [u8; 32] = seed_v.as_slice().try_into().unwrap();
    let b_pub: [u8; MLDSA_PUB] = b_pub_v.as_slice().try_into().unwrap();
    let app_pub: [u8; MLKEM_PUB] = app_pub_v.as_slice().try_into().unwrap();
    let spk_pub: [u8; MLKEM_PUB] = spk_pub_v.as_slice().try_into().unwrap();
    let eph: [u8; 64] = eph_v.as_slice().try_into().unwrap();
    let opk_pub: Option<[u8; MLKEM_PUB]> = if opk_id != 0 && opk_pub_v.len() == MLKEM_PUB {
        Some(opk_pub_v.as_slice().try_into().unwrap())
    } else {
        None
    };
    let bundle = RecipientBundle {
        account_key_pub: &b_pub,
        app_kem_pub: &app_pub,
        signed_prekey_pub: &spk_pub,
        spk_id: spk_id as u32,
        one_time: opk_pub.as_ref().map(|p| (opk_id as u32, p)),
    };
    let hs = match build_handshake(&a_pub, &seed, &bundle, &eph, send_time as u64) {
        Ok(h) => h,
        Err(_) => return null,
    };
    let session = SessionState::init_initiator(
        hs.transcript_hash,
        hs.session.root_key,
        hs.session.sending_chain_key,
        hs.eph_kem_pub_a,
        hs.eph_kem_sk_a,
        hs.signed_prekey_pub_b,
    );
    let out = cat_lp(&hs.bytes, &session.to_bytes());
    match env.byte_array_from_slice(&out) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// Bob: process_handshake + init_responder → session blob (single output).
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeE2eProcessHandshake<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    hs: JByteArray<'local>,
    bob_account_id: JByteArray<'local>,
    bob_app_kem_pub: JByteArray<'local>,
    bob_app_kem_sk: JByteArray<'local>,
    bob_spk_pub: JByteArray<'local>,
    bob_spk_sk: JByteArray<'local>,
    bob_opk_pub: JByteArray<'local>,
    bob_opk_sk: JByteArray<'local>,
    now: jlong,
    accept_skew: jlong,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    macro_rules! ba {
        ($x:expr) => {
            match env.convert_byte_array($x) {
                Ok(b) => b,
                Err(_) => return null,
            }
        };
    }
    let hs_v = ba!(hs);
    let acc_v = ba!(bob_account_id);
    let app_pub_v = ba!(bob_app_kem_pub);
    let app_sk_v = ba!(bob_app_kem_sk);
    let spk_pub_v = ba!(bob_spk_pub);
    let spk_sk_v = ba!(bob_spk_sk);
    let opk_pub_v = ba!(bob_opk_pub);
    let opk_sk_v = ba!(bob_opk_sk);
    if acc_v.len() != 32
        || app_pub_v.len() != MLKEM_PUB
        || app_sk_v.len() != MLKEM_SK
        || spk_pub_v.len() != MLKEM_PUB
        || spk_sk_v.len() != MLKEM_SK
    {
        return null;
    }
    // all lengths checked above (return null otherwise) — try_into does not panic
    let acc_id: [u8; 32] = acc_v.as_slice().try_into().unwrap();
    let app_pub: [u8; MLKEM_PUB] = app_pub_v.as_slice().try_into().unwrap();
    let spk_pub: [u8; MLKEM_PUB] = spk_pub_v.as_slice().try_into().unwrap();
    let opk: Option<([u8; MLKEM_PUB], &[u8])> =
        if opk_pub_v.len() == MLKEM_PUB && opk_sk_v.len() == MLKEM_SK {
            Some((
                opk_pub_v.as_slice().try_into().unwrap(),
                opk_sk_v.as_slice(),
            ))
        } else {
            None
        };
    let keys = RecipientKeys {
        account_id: &acc_id,
        app_kem_pub: &app_pub,
        app_kem_sk: &app_sk_v,
        signed_prekey_pub: &spk_pub,
        signed_prekey_sk: &spk_sk_v,
        one_time: opk.as_ref().map(|(p, s)| (p, *s)),
    };
    let proc = match process_handshake(&hs_v, &keys, now as u64, accept_skew as u64) {
        Ok(p) => p,
        Err(_) => return null,
    };
    let session = SessionState::init_responder(
        proc.transcript_hash,
        proc.session.root_key,
        proc.session.sending_chain_key,
        proc.eph_kem_pub_a,
        spk_pub,
        spk_sk_v.to_vec(),
    );
    match env.byte_array_from_slice(&session.to_bytes()) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// seal_blob(blob_key[32], nonce[12], input) → sealed byte[].
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeE2eSealBlob<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    blob_key: JByteArray<'local>,
    nonce: JByteArray<'local>,
    input: JByteArray<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let key_v = match env.convert_byte_array(blob_key) {
        Ok(b) => b,
        Err(_) => return null,
    };
    let n_v = match env.convert_byte_array(nonce) {
        Ok(b) => b,
        Err(_) => return null,
    };
    let inp = match env.convert_byte_array(input) {
        Ok(b) => b,
        Err(_) => return null,
    };
    if key_v.len() != 32 || n_v.len() != 12 {
        return null;
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&key_v);
    let mut n = [0u8; 12];
    n.copy_from_slice(&n_v);
    match env.byte_array_from_slice(&seal_blob(&key, &n, &inp)) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// open_blob(blob_key[32], sealed) → padded plaintext byte[] (or null).
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeE2eOpenBlob<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    blob_key: JByteArray<'local>,
    sealed_blob: JByteArray<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let key_v = match env.convert_byte_array(blob_key) {
        Ok(b) => b,
        Err(_) => return null,
    };
    let sealed = match env.convert_byte_array(sealed_blob) {
        Ok(b) => b,
        Err(_) => return null,
    };
    if key_v.len() != 32 {
        return null;
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&key_v);
    match open_blob(&key, &sealed) {
        Some(pt) => match env.byte_array_from_slice(&pt) {
            Ok(arr) => arr.into_raw(),
            Err(_) => null,
        },
        None => null,
    }
}

/// blob_id = SHA-256(sealed) → byte[32].
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeE2eBlobId<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    sealed_blob: JByteArray<'local>,
) -> jbyteArray {
    let null = std::ptr::null_mut();
    let sealed = match env.convert_byte_array(sealed_blob) {
        Ok(b) => b,
        Err(_) => return null,
    };
    match env.byte_array_from_slice(&media_blob_id(&sealed)) {
        Ok(arr) => arr.into_raw(),
        Err(_) => null,
    }
}

/// pad_len(n) — target size after padding.
#[no_mangle]
pub extern "system" fn Java_quest_montana_app_MtBindings_nativeE2ePadLen(
    _env: JNIEnv,
    _class: JClass,
    n: jlong,
) -> jlong {
    media_pad_len(n as usize) as jlong
}
