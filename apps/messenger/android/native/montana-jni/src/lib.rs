//! The Montana core for Android: the doors the client path needs, each one the same composition of
//! the core's crates as its iOS twin in mt-bindings/src/ffi_c.rs. No derivation is written here —
//! every quantity is computed by mt-mnemonic and mt-crypto; this file only carries bytes across JNI.
//! `tests` below prove each door against the iOS door on the Mac.

use mt_codec::domain;
use mt_crypto::keypair_from_seed;
use mt_mnemonic::{mldsa_seed_for_role, mnemonic_to_entropy, mnemonic_to_master_seed};
use zeroize::Zeroizing;

pub const ABI_VERSION: u32 = parse_u32(env!("MT_ABI_VERSION"));
pub const PUBKEY_LEN: usize = 1952;
pub const SECKEY_LEN: usize = 4032;

const fn parse_u32(s: &str) -> u32 {
    let b = s.as_bytes();
    let mut i = 0;
    let mut v = 0u32;
    while i < b.len() {
        v = v * 10 + (b[i] - b'0') as u32;
        i += 1;
    }
    v
}

// ─────────── the doors, platform-free (iOS twin in brackets) ───────────

/// A fresh identity, drawn by the core from its own health-tested sources (mt_generate_mnemonic).
pub fn generate() -> Option<Zeroizing<String>> {
    mt_mnemonic::generate_mnemonic().ok()
}

/// 24 words → master seed[64] (mt_mnemonic_to_master_seed).
pub fn master_seed(words: &str) -> Option<Zeroizing<[u8; 64]>> {
    mnemonic_to_master_seed(words).ok().map(Zeroizing::new)
}

/// 24 words → entropy[32] (mt_mnemonic_to_entropy).
pub fn entropy(words: &str) -> Option<Zeroizing<[u8; 32]>> {
    mnemonic_to_entropy(words).ok().map(Zeroizing::new)
}

/// master seed + role → 32-byte role seed (mt_mldsa_seed_for_role).
pub fn role_seed(master: &[u8; 64], role: &[u8]) -> Zeroizing<[u8; 32]> {
    Zeroizing::new(mldsa_seed_for_role(master, role))
}

/// 24 words → the person's ML-DSA-65 signing keys, pk[1952] ‖ sk[4032] (mt_seed_keys).
pub fn seed_keys(words: &str) -> Option<Zeroizing<Vec<u8>>> {
    let master = master_seed(words)?;
    let sign_seed = role_seed(&master, domain::ACCOUNT_KEY);
    let (pk, sk) = keypair_from_seed(&sign_seed).ok()?;
    let mut out = Zeroizing::new(Vec::with_capacity(PUBKEY_LEN + SECKEY_LEN));
    out.extend_from_slice(pk.as_bytes());
    out.extend_from_slice(sk.as_bytes());
    Some(out)
}

/// Bytes drawn by the core from its own sources — a copy's salt (mt_random_fast); None when the core refuses.
pub fn random(len: usize) -> Option<Vec<u8>> {
    if len == 0 || len > 4096 { return None; }
    let mut out = vec![0u8; len];
    mt_mnemonic::random_fast(&mut out).ok()?;
    Some(out)
}

/// entropy[32] → history_key[32]: HKDF-SHA-256(salt=0×32, ikm=entropy, info="mt-history-key") (mt_history_key).
pub fn history_key(entropy: &[u8; 32]) -> Zeroizing<[u8; 32]> {
    let prk = Zeroizing::new(mt_mnemonic::hmac_sha256(&[0u8; 32], entropy));
    let okm = Zeroizing::new(mt_mnemonic::hkdf_expand(&prk[..], domain::MSG_HISTORY_KEY, 32));
    let mut out = Zeroizing::new([0u8; 32]);
    out.copy_from_slice(&okm);
    out
}

/// Which conversation a sealed block belongs to, readable only under the history key (mt_archive_peek_conv).
pub fn archive_peek_conv(hk: &[u8; 32], owner: &[u8; 32], sealed: &[u8]) -> Option<[u8; 32]> {
    mt_messenger_e2e::archive::peek_conv(hk, owner, sealed)
}

/// A sealed block filed as-stored into the chat's log: 1 appended, 0 already held, <0 refused (mt_archive_ingest).
pub fn archive_ingest(base: &str, chat: &str, hk: &[u8; 32], owner: &[u8; 32], sealed: &[u8]) -> i32 {
    let store = match mt_messenger_e2e::archive::ArchiveStore::open(base) {
        Ok(s) => s,
        Err(_) => return -5, // MT_ERR_IO
    };
    match store.ingest_block(chat, hk, owner, sealed) {
        Ok(true) => 1,
        Ok(false) => 0,
        Err(e) if e.kind() == std::io::ErrorKind::InvalidData => -4, // MT_ERR_DECODE
        Err(_) => -5,
    }
}

/// entropy[32] → media_key[32]: HKDF-SHA-256(salt=0×32, ikm=entropy, info="mt-media-key"), a branch apart from history (mt_media_key).
pub fn media_key(entropy: &[u8; 32]) -> Zeroizing<[u8; 32]> {
    let prk = Zeroizing::new(mt_mnemonic::hmac_sha256(&[0u8; 32], entropy));
    let okm = Zeroizing::new(mt_mnemonic::hkdf_expand(&prk[..], domain::MSG_MEDIA_KEY, 32));
    let mut out = Zeroizing::new([0u8; 32]);
    out.copy_from_slice(&okm);
    out
}

/// device_id[16] → writer_tag[4]: SHA-256("mt-history-writer" ‖ 0 ‖ device_id)[0..4], the nonces of one seed's devices kept apart (mt_writer_tag).
pub fn writer_tag(device: &[u8; 16]) -> [u8; 4] {
    mt_messenger_e2e::archive::writer_tag(device)
}

/// One letter sealed under the history key onto the chat's log; the core numbers the block, so no nonce repeats (mt_archive_append).
#[allow(clippy::too_many_arguments)]
pub fn archive_append(base: &str, chat: &str, hk: &[u8; 32], owner: &[u8; 32], device: &[u8; 16], conv: &[u8; 32], dir: u8, send_time: u64, content: &[u8]) -> i32 {
    let store = match mt_messenger_e2e::archive::ArchiveStore::open(base) {
        Ok(s) => s,
        Err(_) => return -5, // MT_ERR_IO
    };
    match store.append_item(chat, hk, owner, device, conv, dir, send_time, content) {
        Ok(_) => 0,
        Err(_) => -5,
    }
}

/// (writer_tag, block_seq) of a sealed block, read off its nonce prefix without opening it (mt_archive_block_id).
pub fn archive_block_id(sealed: &[u8]) -> Option<([u8; 4], u64)> {
    Some((mt_messenger_e2e::archive::block_writer_tag(sealed)?, mt_messenger_e2e::archive::block_seq_of(sealed)?))
}

/// This writer's sealed blocks of one chat from a number on, (u32 LE ‖ sealed)×N — what the twin is handed (mt_archive_export).
pub fn archive_export(base: &str, chat: &str, wt: &[u8; 4], from_seq: u64) -> Option<Vec<u8>> {
    let store = mt_messenger_e2e::archive::ArchiveStore::open(base).ok()?;
    store.export_mine(chat, wt, from_seq).ok()
}

/// One sealed block opened under the history key, in the canonical block encoding — the archive's reading road (mt_archive_open_block).
pub fn archive_open_block(hk: &[u8; 32], owner: &[u8; 32], sealed: &[u8]) -> Option<Vec<u8>> {
    let block = mt_messenger_e2e::archive::open_block(hk, owner, sealed)?;
    Some(mt_messenger_e2e::archive::encode_block(&block))
}

/// A file sealed under the media key into the chat's Media folder — another app sees ciphertext (mt_archive_put_media).
pub fn archive_put_media(base: &str, chat: &str, bid: &str, mk: &[u8; 32], owner: &[u8; 32], data: &[u8]) -> bool {
    match mt_messenger_e2e::archive::ArchiveStore::open(base) {
        Ok(store) => store.put_media(chat, bid, mk, owner, data).is_ok(),
        Err(_) => false,
    }
}

/// A sealed file of the chat's Media folder opened under the media key, or None (mt_archive_get_media).
pub fn archive_get_media(base: &str, chat: &str, bid: &str, mk: &[u8; 32], owner: &[u8; 32]) -> Option<Vec<u8>> {
    mt_messenger_e2e::archive::ArchiveStore::open(base).ok()?.get_media(chat, bid, mk, owner)
}

/// A card's key: ML-KEM-768 KeyGen from a 64-byte seed, pk[1184] ‖ sk[2400] (mt_mlkem_keypair_from_seed).
pub fn mlkem_keypair(seed: &[u8; 64]) -> Option<Zeroizing<Vec<u8>>> {
    let (pk, sk) = mt_crypto::keypair_from_seed_mlkem(seed).ok()?;
    let mut out = Zeroizing::new(Vec::with_capacity(1184 + 2400));
    out.extend_from_slice(pk.as_bytes());
    out.extend_from_slice(sk.as_bytes());
    Some(out)
}

/// A blob for the node: nonce ‖ Seal(key, nonce, input, AD=mt-media) (mt_e2e_seal_blob).
pub fn seal_blob(key: &[u8; 32], nonce: &[u8; 12], input: &[u8]) -> Vec<u8> {
    mt_messenger_e2e::media::seal_blob(key, nonce, input)
}

/// The blob opened, or None when the key is not its key (mt_e2e_open_blob).
pub fn open_blob(key: &[u8; 32], sealed: &[u8]) -> Option<Vec<u8>> {
    mt_messenger_e2e::media::open_blob(key, sealed)
}

/// A card's key opens what was encapsulated to it: sk[2400] + ct[1088] -> ss[32], implicit rejection
/// (mt_mlkem_decaps). A foreign ciphertext yields garbage, never a refusal — the proof is the seal.
pub fn mlkem_decaps(sk: &[u8], ct: &[u8]) -> Option<Zeroizing<[u8; 32]>> {
    let sk = mt_crypto::MlkemSecretKey::from_slice(sk)?;
    let ct = mt_crypto::MlkemCiphertext::from_slice(ct)?;
    let ss = mt_crypto::mlkem_decapsulate(&sk, &ct).ok()?;
    let mut out = Zeroizing::new([0u8; 32]);
    out.copy_from_slice(ss.as_bytes());
    Some(out)
}

/// The scanner's side: one encapsulation to a card's key, ct[1088] ‖ ss[32] (mt_mlkem_encaps).
pub fn mlkem_encaps(pk: &[u8]) -> Option<Zeroizing<Vec<u8>>> {
    let pk = mt_crypto::MlkemPublicKey::from_slice(pk)?;
    let (ct, ss) = mt_crypto::mlkem_encapsulate(&pk).ok()?;
    let mut out = Zeroizing::new(Vec::with_capacity(1088 + 32));
    out.extend_from_slice(ct.as_bytes());
    out.extend_from_slice(ss.as_bytes());
    Some(out)
}

/// The secret of a first letter, every later tag of the correspondence stands on it (mt_name_first_secret).
pub fn first_secret(ss: &[u8], root: &[u8], ct: &[u8]) -> Zeroizing<[u8; 32]> {
    Zeroizing::new(mt_names::first_secret(ss, root, ct))
}

/// Where a first letter knocks in a window: SHA-256("mt-name-tag" ‖ 0 ‖ root ‖ W little-endian)[0..16] (mt_name_first_tag).
pub fn first_tag(root: &[u8], window: u64) -> [u8; 16] {
    mt_names::first_tag(root, window)
}

// ─────────── the plane of names: the Canon's derivations, the core's own (mt-names) and never rewritten in Kotlin ───────────

/// The normalized name, or None when it breaks a rule of the layer (mt_name_normalize). Nothing is trimmed here: the client trims.
pub fn name_normalize(input: &str) -> Option<String> {
    mt_names::normalize(input).ok()
}

/// The slot of an ALREADY normalized name (mt_name_slot): a name that does not normalize to itself is refused, so no slot
/// is ever computed from what a person typed rather than from what is written.
pub fn name_slot(normalized: &str) -> Option<[u8; 32]> {
    (mt_names::normalize(normalized).as_deref() == Ok(normalized)).then(|| mt_names::slot(normalized))
}

/// The chain's far end, the seed's branch that takes the slot (mt_name_own).
pub fn name_own(master_seed: &[u8], slot: &[u8; 32]) -> Zeroizing<[u8; 32]> {
    Zeroizing::new(mt_names::name_own(master_seed, slot))
}

/// The whole chain of renewals, (NAME_CHAIN_LEN + 1) × 32 bytes, link 0 the anchor (mt_name_chain); every link past the
/// last one published is a secret.
pub fn name_chain(own: &[u8; 32]) -> Zeroizing<Vec<u8>> {
    let mut out = Zeroizing::new(Vec::with_capacity((mt_names::NAME_CHAIN_LEN + 1) * 32));
    for link in mt_names::chain(own) {
        out.extend_from_slice(&link);
    }
    out
}

/// The commitment a taking publishes (mt_name_commit).
pub fn name_commit(slot: &[u8; 32], blind: &[u8; 32], tip: &[u8; 32]) -> [u8; 32] {
    mt_names::commit(slot, blind, tip)
}

/// One renewal's proof: the link hashes once to the link published before it (mt_name_verify_link).
pub fn name_verify_link(prev: &[u8; 32], link: &[u8; 32]) -> bool {
    mt_names::verify_link(prev, link)
}

/// The seed of a name's contact key; the ML-KEM-768 pair is drawn from it by the caller (mt_name_contact_seed).
pub fn name_contact_seed(master_seed: &[u8], slot: &[u8; 32]) -> Zeroizing<[u8; 64]> {
    Zeroizing::new(mt_names::contact_seed(master_seed, slot))
}

// ─────────── the channel's doors: a machine's answering identity, its signature, the Noise_PQ XX handshake ───────────

/// seed[32] → a machine's answering identity, ML-DSA-65 pk[1952] ‖ sk[4032] (mt_mldsa_keypair_from_seed).
pub fn mldsa_keypair(seed: &[u8; 32]) -> Option<Zeroizing<Vec<u8>>> {
    let (pk, sk) = keypair_from_seed(seed).ok()?;
    let mut out = Zeroizing::new(Vec::with_capacity(PUBKEY_LEN + SECKEY_LEN));
    out.extend_from_slice(pk.as_bytes());
    out.extend_from_slice(sk.as_bytes());
    Some(out)
}

/// An ML-DSA-65 signature[3309] of `msg` under sk[4032] (mt_sign).
pub fn sign(sk: &[u8], msg: &[u8]) -> Option<Vec<u8>> {
    let sk = mt_crypto::SecretKey::from_slice(sk)?;
    mt_crypto::sign(&sk, msg).ok().map(|s| s.as_bytes().to_vec())
}

/// Whether sig[3309] is pk[1952]'s signature of `msg` (mt_verify).
pub fn verify(pk: &[u8], msg: &[u8], sig: &[u8]) -> bool {
    match (mt_crypto::PublicKey::from_slice(pk), mt_crypto::Signature::from_slice(sig)) {
        (Some(p), Some(s)) => mt_crypto::verify(&p, msg, &s),
        _ => false,
    }
}

/// Initiator: the responder's KEM pk[1184] and a fresh identity seed[32] → msg1[2272] and the state for msg2 (mt_noise_initiator_msg1).
pub fn noise_initiator_msg1(responder_kem_pk: &[u8], seed: &[u8; 32]) -> Option<(Vec<u8>, mt_noise_pq::InitiatorMsg1Sent)> {
    let pk = mt_crypto::MlkemPublicKey::from_slice(responder_kem_pk)?;
    let (id_pk, id_sk) = keypair_from_seed(seed).ok()?;
    let (wire, state) = mt_noise_pq::initiator_send_msg1(&pk, id_sk, id_pk).ok()?;
    Some((wire[..].to_vec(), state))
}

/// Initiator: msg2[6349] read under the state of msg1 → the state for msg3; a forged msg2 is refused (mt_noise_initiator_msg2).
pub fn noise_initiator_msg2(state: mt_noise_pq::InitiatorMsg1Sent, msg2: &[u8]) -> Option<mt_noise_pq::InitiatorMsg2Received> {
    if msg2.len() != mt_noise_pq::NOISE_PQ_MSG2_SIZE { return None; }
    mt_noise_pq::initiator_receive_msg2(msg2, state).ok()
}

/// Initiator: msg3[5261] ‖ the session, sk_i_to_r[32] ‖ sk_r_to_i[32] ‖ channel_hash[32] (mt_noise_initiator_msg3).
pub fn noise_initiator_msg3(state: mt_noise_pq::InitiatorMsg2Received) -> Option<Zeroizing<Vec<u8>>> {
    let (wire, s) = mt_noise_pq::initiator_send_msg3(state).ok()?;
    let mut out = Zeroizing::new(Vec::with_capacity(mt_noise_pq::NOISE_PQ_MSG3_SIZE + 96));
    out.extend_from_slice(&wire[..]);
    session(&mut out, &s);
    Some(out)
}

/// Responder: its KEM sk[2400], a fresh identity seed[32] and msg1[2272] → msg2[6349] and the state for msg3 (mt_noise_responder_msg1).
pub fn noise_responder_msg1(kem_sk: &[u8], seed: &[u8; 32], msg1: &[u8]) -> Option<(Vec<u8>, mt_noise_pq::ResponderMsg2Sent)> {
    let sk = mt_crypto::MlkemSecretKey::from_slice(kem_sk)?;
    if msg1.len() != mt_noise_pq::NOISE_PQ_MSG1_SIZE { return None; }
    let (id_pk, id_sk) = keypair_from_seed(seed).ok()?;
    let st1 = mt_noise_pq::responder_receive_msg1(msg1, &sk, id_sk, id_pk).ok()?;
    let (wire, st2) = mt_noise_pq::responder_send_msg2(st1).ok()?;
    Some((wire[..].to_vec(), st2))
}

/// Responder: msg3[5261] under the state of msg2 → the session, sk_i_to_r ‖ sk_r_to_i ‖ channel_hash (mt_noise_responder_msg3).
pub fn noise_responder_msg3(state: mt_noise_pq::ResponderMsg2Sent, msg3: &[u8]) -> Option<Zeroizing<Vec<u8>>> {
    if msg3.len() != mt_noise_pq::NOISE_PQ_MSG3_SIZE { return None; }
    let s = mt_noise_pq::responder_receive_msg3(msg3, state).ok()?;
    let mut out = Zeroizing::new(Vec::with_capacity(96));
    session(&mut out, &s);
    Some(out)
}

fn session(out: &mut Vec<u8>, s: &mt_noise_pq::NoisePqSession) {
    out.extend_from_slice(&s.sk_i_to_r);
    out.extend_from_slice(&s.sk_r_to_i);
    out.extend_from_slice(&s.transcript_hash);
}

// ─────────── JNI: class quest.montana.app.MtBindings ───────────

#[cfg(target_os = "android")]
mod jni_doors {
    use super::*;
    use jni::objects::{JByteArray, JClass, JLongArray, JString};
    use jni::sys::{jboolean, jbyteArray, jint, jlong, jstring, JNI_FALSE, JNI_TRUE};
    use jni::JNIEnv;

    fn words(env: &mut JNIEnv, s: &JString) -> Option<Zeroizing<String>> {
        env.get_string(s).ok().map(|j| Zeroizing::new(String::from(j)))
    }
    fn bytes(env: &mut JNIEnv, b: &[u8]) -> jbyteArray {
        env.byte_array_from_slice(b).map(|a| a.into_raw()).unwrap_or(std::ptr::null_mut())
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeAbiVersion(_e: JNIEnv, _c: JClass) -> jint {
        ABI_VERSION as jint
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeGenerateMnemonic(mut env: JNIEnv, _c: JClass) -> jstring {
        match generate() {
            Some(m) => env.new_string(m.as_str()).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut()),
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMnemonicToMasterSeed<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, m: JString<'l>,
    ) -> jbyteArray {
        match words(&mut env, &m).and_then(|w| master_seed(&w)) {
            Some(s) => bytes(&mut env, &s[..]),
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMnemonicToEntropy<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, m: JString<'l>,
    ) -> jbyteArray {
        match words(&mut env, &m).and_then(|w| entropy(&w)) {
            Some(e) => bytes(&mut env, &e[..]),
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeSeedKeys<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, m: JString<'l>,
    ) -> jbyteArray {
        match words(&mut env, &m).and_then(|w| seed_keys(&w)) {
            Some(k) => bytes(&mut env, &k[..]),
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeRoleSeed<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, master: JByteArray<'l>, role: JString<'l>,
    ) -> jbyteArray {
        let m = match env.convert_byte_array(&master) {
            Ok(v) if v.len() == 64 => Zeroizing::new(v),
            _ => return std::ptr::null_mut(),
        };
        let role: String = match env.get_string(&role) {
            Ok(s) => s.into(),
            Err(_) => return std::ptr::null_mut(),
        };
        let mut arr = Zeroizing::new([0u8; 64]);
        arr.copy_from_slice(&m);
        let seed = role_seed(&arr, role.as_bytes());
        bytes(&mut env, &seed[..])
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeRandom(mut env: JNIEnv, _c: JClass, len: jint) -> jbyteArray {
        match random(len.max(0) as usize) {
            Some(b) => bytes(&mut env, &b),
            None => std::ptr::null_mut(),
        }
    }

    fn key32(env: &mut JNIEnv, b: &JByteArray) -> Option<Zeroizing<[u8; 32]>> {
        let v = Zeroizing::new(env.convert_byte_array(b).ok()?);
        if v.len() != 32 { return None; }
        let mut k = Zeroizing::new([0u8; 32]);
        k.copy_from_slice(&v);
        Some(k)
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMlkemKeypair<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, seed: JByteArray<'l>,
    ) -> jbyteArray {
        let v = match env.convert_byte_array(&seed) { Ok(v) if v.len() == 64 => Zeroizing::new(v), _ => return std::ptr::null_mut() };
        let mut s = Zeroizing::new([0u8; 64]);
        s.copy_from_slice(&v);
        match mlkem_keypair(&s) { Some(k) => bytes(&mut env, &k[..]), None => std::ptr::null_mut() }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeSealBlob<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, key: JByteArray<'l>, nonce: JByteArray<'l>, input: JByteArray<'l>,
    ) -> jbyteArray {
        let (Some(k), Ok(n), Ok(i)) = (key32(&mut env, &key), env.convert_byte_array(&nonce), env.convert_byte_array(&input)) else {
            return std::ptr::null_mut();
        };
        if n.len() != 12 { return std::ptr::null_mut(); }
        let mut nn = [0u8; 12];
        nn.copy_from_slice(&n);
        let out = seal_blob(&k, &nn, &i);
        bytes(&mut env, &out)
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeOpenBlob<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, key: JByteArray<'l>, sealed: JByteArray<'l>,
    ) -> jbyteArray {
        let (Some(k), Ok(s)) = (key32(&mut env, &key), env.convert_byte_array(&sealed)) else { return std::ptr::null_mut() };
        match open_blob(&k, &s) { Some(p) => bytes(&mut env, &p), None => std::ptr::null_mut() }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMlkemDecaps<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, sk: JByteArray<'l>, ct: JByteArray<'l>,
    ) -> jbyteArray {
        let (Ok(s), Ok(c)) = (env.convert_byte_array(&sk), env.convert_byte_array(&ct)) else { return std::ptr::null_mut() };
        let s = Zeroizing::new(s);
        match mlkem_decaps(&s, &c) { Some(ss) => bytes(&mut env, &ss[..]), None => std::ptr::null_mut() }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMlkemEncaps<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, pk: JByteArray<'l>,
    ) -> jbyteArray {
        let Ok(p) = env.convert_byte_array(&pk) else { return std::ptr::null_mut() };
        match mlkem_encaps(&p) { Some(o) => bytes(&mut env, &o[..]), None => std::ptr::null_mut() }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeFirstSecret<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, ss: JByteArray<'l>, root: JByteArray<'l>, ct: JByteArray<'l>,
    ) -> jbyteArray {
        let (Ok(s), Ok(r), Ok(c)) = (env.convert_byte_array(&ss), env.convert_byte_array(&root), env.convert_byte_array(&ct)) else {
            return std::ptr::null_mut();
        };
        let s = Zeroizing::new(s);
        let out = first_secret(&s, &r, &c);
        bytes(&mut env, &out[..])
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeFirstTag<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, root: JByteArray<'l>, window: jlong,
    ) -> jbyteArray {
        let Ok(r) = env.convert_byte_array(&root) else { return std::ptr::null_mut() };
        let Ok(w) = u64::try_from(window) else { return std::ptr::null_mut() };
        bytes(&mut env, &first_tag(&r, w))
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNameNormalize<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, raw: JString<'l>,
    ) -> jstring {
        let Some(w) = words(&mut env, &raw) else { return std::ptr::null_mut() };
        match name_normalize(&w) {
            Some(n) => env.new_string(n).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut()),
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNameSlot<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, normalized: JString<'l>,
    ) -> jbyteArray {
        let Some(w) = words(&mut env, &normalized) else { return std::ptr::null_mut() };
        match name_slot(&w) {
            Some(sl) => bytes(&mut env, &sl),
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNameOwn<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, master: JByteArray<'l>, slot: JByteArray<'l>,
    ) -> jbyteArray {
        let Ok(m) = env.convert_byte_array(&master) else { return std::ptr::null_mut() };
        let m = Zeroizing::new(m);
        let Some(sl) = key32(&mut env, &slot) else { return std::ptr::null_mut() };
        let own = name_own(&m, &sl);
        bytes(&mut env, &own[..])
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNameChain<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, own: JByteArray<'l>,
    ) -> jbyteArray {
        let Some(o) = key32(&mut env, &own) else { return std::ptr::null_mut() };
        let ch = name_chain(&o);
        bytes(&mut env, &ch)
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNameCommit<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, slot: JByteArray<'l>, blind: JByteArray<'l>, tip: JByteArray<'l>,
    ) -> jbyteArray {
        let (Some(s), Some(b), Some(t)) = (key32(&mut env, &slot), key32(&mut env, &blind), key32(&mut env, &tip)) else {
            return std::ptr::null_mut();
        };
        bytes(&mut env, &name_commit(&s, &b, &t))
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNameVerifyLink<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, prev: JByteArray<'l>, link: JByteArray<'l>,
    ) -> jboolean {
        match (key32(&mut env, &prev), key32(&mut env, &link)) {
            (Some(p), Some(l)) if name_verify_link(&p, &l) => JNI_TRUE,
            _ => JNI_FALSE,
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNameContactSeed<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, master: JByteArray<'l>, slot: JByteArray<'l>,
    ) -> jbyteArray {
        let Ok(m) = env.convert_byte_array(&master) else { return std::ptr::null_mut() };
        let m = Zeroizing::new(m);
        let Some(sl) = key32(&mut env, &slot) else { return std::ptr::null_mut() };
        let seed = name_contact_seed(&m, &sl);
        bytes(&mut env, &seed[..])
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeHistoryKey<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, ent: JByteArray<'l>,
    ) -> jbyteArray {
        match key32(&mut env, &ent) {
            Some(e) => { let hk = history_key(&e); bytes(&mut env, &hk[..]) }
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeArchivePeekConv<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, hk: JByteArray<'l>, owner: JByteArray<'l>, sealed: JByteArray<'l>,
    ) -> jbyteArray {
        let (Some(h), Some(o), Ok(s)) = (key32(&mut env, &hk), key32(&mut env, &owner), env.convert_byte_array(&sealed)) else {
            return std::ptr::null_mut();
        };
        match archive_peek_conv(&h, &o, &s) {
            Some(conv) => bytes(&mut env, &conv),
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeArchiveIngest<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, base: JString<'l>, chat: JString<'l>,
        hk: JByteArray<'l>, owner: JByteArray<'l>, sealed: JByteArray<'l>,
    ) -> jint {
        let base: String = match env.get_string(&base) { Ok(s) => s.into(), Err(_) => return -3 };
        let chat: String = match env.get_string(&chat) { Ok(s) => s.into(), Err(_) => return -3 };
        let (Some(h), Some(o), Ok(s)) = (key32(&mut env, &hk), key32(&mut env, &owner), env.convert_byte_array(&sealed)) else {
            return -1;
        };
        archive_ingest(&base, &chat, &h, &o, &s)
    }

    fn text(env: &mut JNIEnv, s: &JString) -> Option<String> { env.get_string(s).ok().map(String::from) }
    fn dev16(env: &mut JNIEnv, b: &JByteArray) -> Option<[u8; 16]> {
        let v = env.convert_byte_array(b).ok()?;
        if v.len() != 16 { return None; }
        let mut d = [0u8; 16];
        d.copy_from_slice(&v);
        Some(d)
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMediaKey<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, ent: JByteArray<'l>,
    ) -> jbyteArray {
        match key32(&mut env, &ent) {
            Some(e) => { let mk = media_key(&e); bytes(&mut env, &mk[..]) }
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeWriterTag<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, device: JByteArray<'l>,
    ) -> jbyteArray {
        match dev16(&mut env, &device) {
            Some(d) => bytes(&mut env, &writer_tag(&d)),
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeArchiveAppend<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, base: JString<'l>, chat: JString<'l>, hk: JByteArray<'l>, owner: JByteArray<'l>,
        device: JByteArray<'l>, conv: JByteArray<'l>, dir: jint, send_time: jlong, content: JByteArray<'l>,
    ) -> jint {
        let (Some(b), Some(ch)) = (text(&mut env, &base), text(&mut env, &chat)) else { return -3 };
        let (Some(h), Some(o), Some(d), Some(cv)) = (key32(&mut env, &hk), key32(&mut env, &owner), dev16(&mut env, &device), key32(&mut env, &conv)) else {
            return -1;
        };
        let (Ok(dir), Ok(t), Ok(body)) = (u8::try_from(dir), u64::try_from(send_time), env.convert_byte_array(&content)) else { return -1 };
        archive_append(&b, &ch, &h, &o, &d, &cv, dir, t, &body)
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeArchiveBlockId<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, sealed: JByteArray<'l>,
    ) -> jbyteArray {
        let Ok(s) = env.convert_byte_array(&sealed) else { return std::ptr::null_mut() };
        match archive_block_id(&s) {
            Some((wt, seq)) => { let mut out = wt.to_vec(); out.extend_from_slice(&seq.to_le_bytes()); bytes(&mut env, &out) }
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeArchiveExport<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, base: JString<'l>, chat: JString<'l>, wt: JByteArray<'l>, from_seq: jlong,
    ) -> jbyteArray {
        let (Some(b), Some(ch)) = (text(&mut env, &base), text(&mut env, &chat)) else { return std::ptr::null_mut() };
        let (Ok(w), Ok(from)) = (env.convert_byte_array(&wt), u64::try_from(from_seq)) else { return std::ptr::null_mut() };
        let Ok(w4) = <[u8; 4]>::try_from(w.as_slice()) else { return std::ptr::null_mut() };
        match archive_export(&b, &ch, &w4, from) {
            Some(stream) => bytes(&mut env, &stream),
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeArchiveOpenBlock<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, hk: JByteArray<'l>, owner: JByteArray<'l>, sealed: JByteArray<'l>,
    ) -> jbyteArray {
        let (Some(h), Some(o), Ok(s)) = (key32(&mut env, &hk), key32(&mut env, &owner), env.convert_byte_array(&sealed)) else {
            return std::ptr::null_mut();
        };
        match archive_open_block(&h, &o, &s) {
            Some(plain) => bytes(&mut env, &plain),
            None => std::ptr::null_mut(),
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeArchivePutMedia<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, base: JString<'l>, chat: JString<'l>, bid: JString<'l>,
        mk: JByteArray<'l>, owner: JByteArray<'l>, data: JByteArray<'l>,
    ) -> jboolean {
        let (Some(b), Some(ch), Some(id)) = (text(&mut env, &base), text(&mut env, &chat), text(&mut env, &bid)) else { return JNI_FALSE };
        let (Some(m), Some(o), Ok(d)) = (key32(&mut env, &mk), key32(&mut env, &owner), env.convert_byte_array(&data)) else { return JNI_FALSE };
        if archive_put_media(&b, &ch, &id, &m, &o, &d) { JNI_TRUE } else { JNI_FALSE }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeArchiveGetMedia<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, base: JString<'l>, chat: JString<'l>, bid: JString<'l>,
        mk: JByteArray<'l>, owner: JByteArray<'l>,
    ) -> jbyteArray {
        let (Some(b), Some(ch), Some(id)) = (text(&mut env, &base), text(&mut env, &chat), text(&mut env, &bid)) else { return std::ptr::null_mut() };
        let (Some(m), Some(o)) = (key32(&mut env, &mk), key32(&mut env, &owner)) else { return std::ptr::null_mut() };
        match archive_get_media(&b, &ch, &id, &m, &o) {
            Some(plain) => bytes(&mut env, &plain),
            None => std::ptr::null_mut(),
        }
    }
    // ── the channel's doors ──

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeMldsaKeypair<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, seed: JByteArray<'l>,
    ) -> jbyteArray {
        let Some(s) = key32(&mut env, &seed) else { return std::ptr::null_mut() };
        match mldsa_keypair(&s) { Some(k) => bytes(&mut env, &k[..]), None => std::ptr::null_mut() }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeSign<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, sk: JByteArray<'l>, msg: JByteArray<'l>,
    ) -> jbyteArray {
        let (Ok(s), Ok(m)) = (env.convert_byte_array(&sk), env.convert_byte_array(&msg)) else { return std::ptr::null_mut() };
        let s = Zeroizing::new(s);
        match sign(&s, &m) { Some(sig) => bytes(&mut env, &sig), None => std::ptr::null_mut() }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeVerify<'l>(
        env: JNIEnv<'l>, _c: JClass<'l>, pk: JByteArray<'l>, msg: JByteArray<'l>, sig: JByteArray<'l>,
    ) -> jboolean {
        let (Ok(p), Ok(m), Ok(s)) = (env.convert_byte_array(&pk), env.convert_byte_array(&msg), env.convert_byte_array(&sig)) else { return JNI_FALSE };
        if verify(&p, &m, &s) { JNI_TRUE } else { JNI_FALSE }
    }

    /// A state between two messages of the handshake lives in the core as a box; Kotlin holds only its address.
    fn hold<T>(env: &mut JNIEnv, out: &JLongArray, state: T) -> bool {
        let h = Box::into_raw(Box::new(state));
        if env.set_long_array_region(out, 0, &[h as jlong]).is_ok() { return true; }
        // SAFETY: `h` was made by Box::into_raw just above and handed to nobody; it is taken back once, here.
        drop(unsafe { Box::from_raw(h) });
        false
    }

    /// # Safety
    /// `h` is an address `hold` (or a consuming door) gave Kotlin for a state of exactly the type `T`, and Kotlin hands
    /// each address back once (MtBindings: every call consumes the state it is given) — the box is taken back whole.
    unsafe fn take<T>(h: jlong) -> Option<T> {
        if h == 0 { return None; }
        Some(*Box::from_raw(h as *mut T))
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNoiseInitiator1<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, kem_pk: JByteArray<'l>, seed: JByteArray<'l>, out: JLongArray<'l>,
    ) -> jbyteArray {
        let (Ok(pk), Some(s)) = (env.convert_byte_array(&kem_pk), key32(&mut env, &seed)) else { return std::ptr::null_mut() };
        let Some((msg1, state)) = noise_initiator_msg1(&pk, &s) else { return std::ptr::null_mut() };
        if !hold(&mut env, &out, state) { return std::ptr::null_mut(); }
        bytes(&mut env, &msg1)
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNoiseInitiator2<'l>(
        env: JNIEnv<'l>, _c: JClass<'l>, state: jlong, msg2: JByteArray<'l>,
    ) -> jlong {
        // SAFETY: `state` is the address nativeNoiseInitiator1 held for an InitiatorMsg1Sent; consumed here, whatever the answer.
        let Some(st) = (unsafe { take::<mt_noise_pq::InitiatorMsg1Sent>(state) }) else { return 0 };
        let Ok(m) = env.convert_byte_array(&msg2) else { return 0 };
        noise_initiator_msg2(st, &m).map(|s| Box::into_raw(Box::new(s)) as jlong).unwrap_or(0)
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNoiseInitiator3<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, state: jlong,
    ) -> jbyteArray {
        // SAFETY: `state` is the address nativeNoiseInitiator2 gave for an InitiatorMsg2Received; consumed here.
        let Some(st) = (unsafe { take::<mt_noise_pq::InitiatorMsg2Received>(state) }) else { return std::ptr::null_mut() };
        match noise_initiator_msg3(st) { Some(o) => bytes(&mut env, &o[..]), None => std::ptr::null_mut() }
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNoiseResponder1<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, kem_sk: JByteArray<'l>, seed: JByteArray<'l>, msg1: JByteArray<'l>, out: JLongArray<'l>,
    ) -> jbyteArray {
        let (Ok(sk), Some(s), Ok(m)) = (env.convert_byte_array(&kem_sk), key32(&mut env, &seed), env.convert_byte_array(&msg1)) else {
            return std::ptr::null_mut();
        };
        let sk = Zeroizing::new(sk);
        let Some((msg2, state)) = noise_responder_msg1(&sk, &s, &m) else { return std::ptr::null_mut() };
        if !hold(&mut env, &out, state) { return std::ptr::null_mut(); }
        bytes(&mut env, &msg2)
    }

    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNoiseResponder3<'l>(
        mut env: JNIEnv<'l>, _c: JClass<'l>, state: jlong, msg3: JByteArray<'l>,
    ) -> jbyteArray {
        // SAFETY: `state` is the address nativeNoiseResponder1 held for a ResponderMsg2Sent; consumed here, whatever the answer.
        let Some(st) = (unsafe { take::<mt_noise_pq::ResponderMsg2Sent>(state) }) else { return std::ptr::null_mut() };
        let Ok(m) = env.convert_byte_array(&msg3) else { return std::ptr::null_mut() };
        match noise_responder_msg3(st, &m) { Some(o) => bytes(&mut env, &o[..]), None => std::ptr::null_mut() }
    }

    /// A state abandoned between messages (the peer fell silent): kind 1 — after msg1, 2 — after msg2, 3 — the responder's.
    #[no_mangle]
    pub extern "system" fn Java_quest_montana_app_MtBindings_nativeNoiseFree(_e: JNIEnv, _c: JClass, kind: jint, state: jlong) {
        // SAFETY: `state` is an address held for the type `kind` names and never handed back before; taken back once, dropped.
        unsafe {
            match kind {
                1 => drop(take::<mt_noise_pq::InitiatorMsg1Sent>(state)),
                2 => drop(take::<mt_noise_pq::InitiatorMsg2Received>(state)),
                3 => drop(take::<mt_noise_pq::ResponderMsg2Sent>(state)),
                _ => {}
            }
        }
    }
}

// ─────────── proof: every door answers as the iOS door (mt-bindings C ABI) ───────────

#[cfg(test)]
mod tests {
    use super::*;
    use mt_bindings::ffi_c;
    use std::ffi::CString;

    fn some_words() -> String { generate().expect("the core draws a phrase").to_string() }

    #[test]
    fn mlkem_keypair_matches_ios() {
        let seed: [u8; 64] = core::array::from_fn(|i| (i * 7 + 3) as u8);
        let mut pk = vec![0u8; 1184];
        let mut sk = vec![0u8; 2400];
        assert_eq!(unsafe { ffi_c::mt_mlkem_keypair_from_seed(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) }, 0);
        let ours = mlkem_keypair(&seed).unwrap();
        assert_eq!(&ours[..1184], &pk[..]);
        assert_eq!(&ours[1184..], &sk[..]);
    }

    #[test]
    fn blob_seal_matches_ios_and_opens() {
        let key = [9u8; 32];
        let nonce = [4u8; 12];
        let msg = b"montana card payload";
        let mut out: *mut u8 = std::ptr::null_mut();
        let mut len = 0usize;
        assert_eq!(unsafe { mt_bindings::ffi_e2e::mt_e2e_seal_blob(key.as_ptr(), nonce.as_ptr(), msg.as_ptr(), msg.len(), &mut out, &mut len) }, 0);
        let theirs = unsafe { std::slice::from_raw_parts(out, len) }.to_vec();
        unsafe { mt_bindings::ffi_e2e::mt_e2e_free(out, len) };
        let ours = seal_blob(&key, &nonce, msg);
        assert_eq!(ours, theirs);
        assert_eq!(open_blob(&key, &ours).as_deref(), Some(&msg[..]));
        assert!(open_blob(&[1u8; 32], &ours).is_none());
    }

    #[test]
    fn first_contact_matches_ios() {
        // The scanner's side through the iOS doors: encapsulate to the card key, derive the first secret.
        let seed: [u8; 64] = core::array::from_fn(|i| (i * 5 + 1) as u8);
        let kp = mlkem_keypair(&seed).unwrap();
        let (pk, sk) = (&kp[..1184], &kp[1184..]);
        let mut ct = vec![0u8; 1088];
        let mut ss = [0u8; 32];
        assert_eq!(unsafe { ffi_c::mt_mlkem_encaps(pk.as_ptr(), ct.as_mut_ptr(), ss.as_mut_ptr()) }, 0);
        let mut theirs = [0u8; 32];
        assert_eq!(unsafe { mt_bindings::ffi_names::mt_name_first_secret(ss.as_ptr(), 32, pk.as_ptr(), 1184, ct.as_ptr(), 1088, theirs.as_mut_ptr()) }, 0);
        // The holder's side through ours: the same shared secret, the same first secret.
        let mine = mlkem_decaps(sk, &ct).unwrap();
        assert_eq!(&mine[..], &ss[..]);
        let mut ios_ss = [0u8; 32];
        assert_eq!(unsafe { ffi_c::mt_mlkem_decaps(sk.as_ptr(), ct.as_ptr(), ios_ss.as_mut_ptr()) }, 0);
        assert_eq!(ios_ss, ss);
        assert_eq!(&first_secret(&mine[..], pk, &ct)[..], &theirs[..]);
    }

    #[test]
    fn first_tag_is_the_ios_door() {
        // A root of no pattern and three windows, the third past 2^32: a window written big-endian, a window cut to 32 bits,
        // or another domain over the root each give other bytes than the iOS door does.
        let root: Vec<u8> = (0..1184).map(|i| ((i * 37 + 11) % 251) as u8).collect();
        for w in [1000u64, 1001, (1u64 << 32) + 7] {
            let mut theirs = [0u8; 16];
            assert_eq!(unsafe { mt_bindings::ffi_names::mt_name_first_tag(root.as_ptr(), root.len(), w, theirs.as_mut_ptr()) }, 0);
            assert_eq!(first_tag(&root, w), theirs);
        }
        assert_ne!(first_tag(&root, 1000), first_tag(&root, 1001));
    }

    #[test]
    fn encaps_opens_under_ios_decaps() {
        // Ours encapsulates (the scanner is Android), the iOS door decapsulates (the card's owner is an iPhone).
        let seed: [u8; 64] = core::array::from_fn(|i| (i * 11 + 2) as u8);
        let kp = mlkem_keypair(&seed).unwrap();
        let (pk, sk) = (&kp[..1184], &kp[1184..]);
        let o = mlkem_encaps(pk).unwrap();
        let (ct, ss) = (&o[..1088], &o[1088..]);
        let mut theirs = [0u8; 32];
        assert_eq!(unsafe { ffi_c::mt_mlkem_decaps(sk.as_ptr(), ct.as_ptr(), theirs.as_mut_ptr()) }, 0);
        assert_eq!(&theirs[..], ss);
    }

    #[test]
    fn abi_version_is_the_cores() {
        assert_eq!(ABI_VERSION, ffi_c::mt_abi_version());
    }

    #[test]
    fn master_seed_and_entropy_match_ios() {
        for _ in 0..3 {
            let w = some_words();
            let c = CString::new(w.clone()).unwrap();
            let mut ms = [0u8; 64];
            let mut en = [0u8; 32];
            assert_eq!(unsafe { ffi_c::mt_mnemonic_to_master_seed(c.as_ptr(), ms.as_mut_ptr()) }, 0);
            assert_eq!(unsafe { ffi_c::mt_mnemonic_to_entropy(c.as_ptr(), en.as_mut_ptr()) }, 0);
            assert_eq!(&master_seed(&w).unwrap()[..], &ms[..]);
            assert_eq!(&entropy(&w).unwrap()[..], &en[..]);
        }
    }

    #[test]
    fn seed_keys_match_ios() {
        let w = some_words();
        let c = CString::new(w.clone()).unwrap();
        let mut pk = vec![0u8; PUBKEY_LEN];
        let mut sk = vec![0u8; SECKEY_LEN];
        assert_eq!(unsafe { ffi_c::mt_seed_keys(c.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) }, 0);
        let ours = seed_keys(&w).unwrap();
        assert_eq!(&ours[..PUBKEY_LEN], &pk[..]);
        assert_eq!(&ours[PUBKEY_LEN..], &sk[..]);
    }

    #[test]
    fn owner_role_seed_matches_ios() {
        let w = some_words();
        let master = master_seed(&w).unwrap();
        let role = b"mt-owner-key";
        let mut out = [0u8; 32];
        assert_eq!(unsafe { ffi_c::mt_mldsa_seed_for_role(master.as_ptr(), role.as_ptr(), role.len(), out.as_mut_ptr()) }, 0);
        assert_eq!(&role_seed(&master, role)[..], &out[..]);
    }

    #[test]
    fn random_is_the_cores() {
        let a = random(32).unwrap();
        let b = random(32).unwrap();
        assert_eq!(a.len(), 32);
        assert_ne!(a, b);
        assert!(random(0).is_none());
        let mut out = [0u8; 32];
        assert_eq!(unsafe { ffi_c::mt_random_fast(out.as_mut_ptr(), 32) }, 0);
    }

    #[test]
    fn history_key_matches_ios() {
        // iOS E2EVault.historyKeyKAT: the frozen vector on 0x55 × 32
        let k = history_key(&[0x55; 32]);
        let hexed: String = k.iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(hexed, "e6a7dc51003770589d9f731c1231c1523be7348c7769383875dd34bd6c578def");
        let e = entropy(&some_words()).unwrap();
        let mut out = [0u8; 32];
        assert_eq!(unsafe { ffi_c::mt_history_key(e.as_ptr(), out.as_mut_ptr()) }, 0);
        assert_eq!(&history_key(&e)[..], &out[..]);
    }

    #[test]
    fn archive_doors_match_ios() {
        // a block this device seals, taken back by both doors into two stores: the same answers, the same files
        let hk = [7u8; 32];
        let owner = [9u8; 32];
        let conv = [3u8; 32];
        let tmp = std::env::temp_dir().join(format!("mt-jni-archive-{}", std::process::id()));
        let (a, b) = (tmp.join("a"), tmp.join("b"));
        use mt_messenger_e2e::archive::{seal_block, HistoryBlock, HistoryItem};
        let item = HistoryItem { conv_id: conv, dir: 1, send_time: 1_700_000_000, content: b"hello".to_vec() };
        let sealed = seal_block(&hk, &owner, &[1u8; 16], &HistoryBlock { block_seq: 1, items: vec![item] });
        assert_eq!(archive_peek_conv(&hk, &owner, &sealed), Some(conv));
        let mut out = [0u8; 32];
        assert_eq!(unsafe { ffi_c::mt_archive_peek_conv(hk.as_ptr(), owner.as_ptr(), sealed.as_ptr(), sealed.len(), out.as_mut_ptr()) }, 0);
        assert_eq!(out, conv);
        let bs = CString::new(b.to_str().unwrap()).unwrap();
        let chat = CString::new("c1").unwrap();
        let ios = unsafe { ffi_c::mt_archive_ingest(bs.as_ptr(), chat.as_ptr(), hk.as_ptr(), owner.as_ptr(), sealed.as_ptr(), sealed.len()) };
        let ours = archive_ingest(a.to_str().unwrap(), "c1", &hk, &owner, &sealed);
        assert_eq!((ours, ios), (1, 1));
        assert_eq!(archive_ingest(a.to_str().unwrap(), "c1", &hk, &owner, &sealed), 0); // held already: merged, not doubled
        assert!(archive_ingest(a.to_str().unwrap(), "c1", &[8u8; 32], &owner, &sealed) < 0); // another key: refused
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn archive_writing_doors_match_ios() {
        // One letter appended by ours into store a and by the iOS door into store b: the logs are the same bytes (a key, a field
        // order or a number told otherwise would part them), the export, the block's identity and the opened canon agree, and the
        // media branch opens under the media key alone.
        let ent = [0x5au8; 32];
        let mut ios_mk = [0u8; 32];
        assert_eq!(unsafe { ffi_c::mt_media_key(ent.as_ptr(), ios_mk.as_mut_ptr()) }, 0);
        assert_eq!(&media_key(&ent)[..], &ios_mk[..]);
        assert_ne!(&media_key(&ent)[..], &history_key(&ent)[..]);
        let dev = [0x21u8; 16];
        let mut ios_wt = [0u8; 4];
        assert_eq!(unsafe { ffi_c::mt_writer_tag(dev.as_ptr(), ios_wt.as_mut_ptr()) }, 0);
        assert_eq!(writer_tag(&dev), ios_wt);
        let (hk, owner, conv) = ([7u8; 32], [9u8; 32], [3u8; 32]);
        let tmp = std::env::temp_dir().join(format!("mt-jni-archive-w-{}", std::process::id()));
        let (a, b) = (tmp.join("a"), tmp.join("b"));
        assert_eq!(archive_append(a.to_str().unwrap(), "c1", &hk, &owner, &dev, &conv, 0, 1_700_000_123, b"first"), 0);
        let (bs, chat) = (CString::new(b.to_str().unwrap()).unwrap(), CString::new("c1").unwrap());
        assert_eq!(unsafe { ffi_c::mt_archive_append(bs.as_ptr(), chat.as_ptr(), hk.as_ptr(), owner.as_ptr(), dev.as_ptr(), conv.as_ptr(), 0, 1_700_000_123, b"first".as_ptr(), 5) }, 0);
        let log = |root: &std::path::Path| std::fs::read(root.join("Chats").join("c1").join("conversation.mtlog")).unwrap();
        assert_eq!(log(&a), log(&b));
        let ours = archive_export(a.to_str().unwrap(), "c1", &ios_wt, 0).unwrap();
        let mut buf = vec![0u8; 1 << 16];
        let n = unsafe { ffi_c::mt_archive_export(bs.as_ptr(), chat.as_ptr(), ios_wt.as_ptr(), 0, buf.as_mut_ptr(), buf.len()) };
        assert_eq!(&ours[..], &buf[..n as usize]);
        let len = u32::from_le_bytes([ours[0], ours[1], ours[2], ours[3]]) as usize;
        let sealed = &ours[4..4 + len];
        let (wt, seq) = archive_block_id(sealed).unwrap();
        let (mut ios_wt2, mut ios_seq) = ([0u8; 4], 0u64);
        assert_eq!(unsafe { ffi_c::mt_archive_block_id(sealed.as_ptr(), sealed.len(), ios_wt2.as_mut_ptr(), &mut ios_seq) }, 0);
        assert_eq!((wt, seq), (ios_wt2, ios_seq));
        let plain = archive_open_block(&hk, &owner, sealed).unwrap();
        let mut obuf = vec![0u8; 4096];
        let on = unsafe { ffi_c::mt_archive_open_block(hk.as_ptr(), owner.as_ptr(), sealed.as_ptr(), sealed.len(), obuf.as_mut_ptr(), obuf.len()) };
        assert_eq!(&plain[..], &obuf[..on as usize]);
        assert!(plain.ends_with(b"first"));
        assert!(archive_open_block(&[8u8; 32], &owner, sealed).is_none());
        let mk = media_key(&ent);
        assert!(archive_put_media(a.to_str().unwrap(), "c1", "face", &mk, &owner, b"picture"));
        let bid = CString::new("face").unwrap();
        let mut mbuf = vec![0u8; 1024];
        let mn = unsafe { ffi_c::mt_archive_get_media(CString::new(a.to_str().unwrap()).unwrap().as_ptr(), chat.as_ptr(), bid.as_ptr(), mk.as_ptr(), owner.as_ptr(), mbuf.as_mut_ptr(), mbuf.len()) };
        assert_eq!(&mbuf[..mn as usize], b"picture");
        assert_eq!(archive_get_media(a.to_str().unwrap(), "c1", "face", &mk, &owner).as_deref(), Some(&b"picture"[..]));
        assert!(archive_get_media(a.to_str().unwrap(), "c1", "face", &hk, &owner).is_none());
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn mldsa_keypair_matches_ios() {
        let seed: [u8; 32] = core::array::from_fn(|i| (i * 5 + 1) as u8);
        let mut pk = vec![0u8; 1952];
        let mut sk = vec![0u8; 4032];
        assert_eq!(unsafe { ffi_c::mt_mldsa_keypair_from_seed(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) }, 0);
        let ours = mldsa_keypair(&seed).unwrap();
        assert_eq!(&ours[..1952], &pk[..]);
        assert_eq!(&ours[1952..], &sk[..]);
    }

    #[test]
    fn signatures_cross_with_ios() {
        let k = mldsa_keypair(&[3u8; 32]).unwrap();
        let (pk, sk) = (&k[..1952], &k[1952..]);
        let msg = b"mt-overlay-register\0nonce-and-channel-hash";
        let ours = sign(sk, msg).unwrap();
        assert_eq!(ours.len(), 3309);
        assert_eq!(unsafe { ffi_c::mt_verify(pk.as_ptr(), msg.as_ptr(), msg.len(), ours.as_ptr()) }, 0);
        let mut theirs = vec![0u8; 3309];
        assert_eq!(unsafe { ffi_c::mt_sign(sk.as_ptr(), msg.as_ptr(), msg.len(), theirs.as_mut_ptr()) }, 0);
        assert!(verify(pk, msg, &theirs));
        // another message, or another key, is refused: a verifier that only checked the length would pass these
        assert!(!verify(pk, b"another message", &theirs));
        let other = mldsa_keypair(&[4u8; 32]).unwrap();
        assert!(!verify(&other[..1952], msg, &theirs));
    }

    fn responder_kem() -> (Vec<u8>, Vec<u8>) {
        let seed: [u8; 64] = core::array::from_fn(|i| (i * 11 + 2) as u8);
        let k = mlkem_keypair(&seed).unwrap();
        (k[..1184].to_vec(), k[1184..].to_vec())
    }

    #[test]
    fn our_initiator_meets_the_ios_responder() {
        use mt_bindings::ffi_noise as n;
        let (kpk, ksk) = responder_kem();
        let (msg1, st1) = noise_initiator_msg1(&kpk, &[7u8; 32]).unwrap();
        assert_eq!(msg1.len(), 2272);
        let mut msg2 = vec![0u8; 6349];
        let mut rst: *mut std::ffi::c_void = std::ptr::null_mut();
        assert_eq!(unsafe { n::mt_noise_responder_msg1(ksk.as_ptr(), [8u8; 32].as_ptr(), msg1.as_ptr(), msg2.as_mut_ptr(), &mut rst) }, 0);
        let st2 = noise_initiator_msg2(st1, &msg2).unwrap();
        let out = noise_initiator_msg3(st2).unwrap();
        assert_eq!(out.len(), 5261 + 96);
        let (mut i2r, mut r2i, mut ch) = ([0u8; 32], [0u8; 32], [0u8; 32]);
        assert_eq!(unsafe { n::mt_noise_responder_msg3(&mut rst, out.as_ptr(), i2r.as_mut_ptr(), r2i.as_mut_ptr(), ch.as_mut_ptr()) }, 0);
        // each direction's key is the same direction's key on the other side: a pair handed back swapped fails here
        assert_eq!(&out[5261..5293], &i2r[..]);
        assert_eq!(&out[5293..5325], &r2i[..]);
        assert_eq!(&out[5325..], &ch[..]);
        assert_ne!(i2r, r2i);
    }

    #[test]
    fn the_ios_initiator_meets_our_responder() {
        use mt_bindings::ffi_noise as n;
        let (kpk, ksk) = responder_kem();
        let mut msg1 = vec![0u8; 2272];
        let mut ist: *mut std::ffi::c_void = std::ptr::null_mut();
        assert_eq!(unsafe { n::mt_noise_initiator_msg1(kpk.as_ptr(), [5u8; 32].as_ptr(), msg1.as_mut_ptr(), &mut ist) }, 0);
        let (msg2, rst) = noise_responder_msg1(&ksk, &[6u8; 32], &msg1).unwrap();
        assert_eq!(msg2.len(), 6349);
        let mut ist2: *mut std::ffi::c_void = std::ptr::null_mut();
        assert_eq!(unsafe { n::mt_noise_initiator_msg2(&mut ist, msg2.as_ptr(), &mut ist2) }, 0);
        let mut msg3 = vec![0u8; 5261];
        let (mut i2r, mut r2i, mut ch) = ([0u8; 32], [0u8; 32], [0u8; 32]);
        assert_eq!(unsafe { n::mt_noise_initiator_msg3(&mut ist2, msg3.as_mut_ptr(), i2r.as_mut_ptr(), r2i.as_mut_ptr(), ch.as_mut_ptr()) }, 0);
        let keys = noise_responder_msg3(rst, &msg3).unwrap();
        assert_eq!(&keys[..32], &i2r[..]);
        assert_eq!(&keys[32..64], &r2i[..]);
        assert_eq!(&keys[64..], &ch[..]);
    }

    #[test]
    fn a_forged_msg2_is_refused() {
        let (kpk, ksk) = responder_kem();
        let (msg1, st1) = noise_initiator_msg1(&kpk, &[7u8; 32]).unwrap();
        let (mut msg2, _rst) = noise_responder_msg1(&ksk, &[8u8; 32], &msg1).unwrap();
        msg2[0] ^= 1;
        assert!(noise_initiator_msg2(st1, &msg2).is_none());
    }

    #[test]
    fn a_wrong_phrase_is_refused() {
        let mut w: Vec<String> = some_words().split(' ').map(String::from).collect();
        w.swap(0, 1);
        let swapped = w.join(" ");
        // a swap almost always breaks the checksum; the core and this door must agree either way
        let c = CString::new(swapped.clone()).unwrap();
        let mut ms = [0u8; 64];
        let ios_ok = unsafe { ffi_c::mt_mnemonic_to_master_seed(c.as_ptr(), ms.as_mut_ptr()) } == 0;
        assert_eq!(master_seed(&swapped).is_some(), ios_ok);
        assert!(master_seed("not a phrase").is_none());
    }

    #[test]
    fn names_are_the_ios_derivations_and_the_canon() {
        fn hex(b: &[u8]) -> String { b.iter().map(|x| format!("{:02x}", x)).collect() }
        // The Canon's own values (MontanaNames.agreesWithCanon, MontanaFirstContact.agreesWithCanon at 2155): a chain hashed
        // the other way, a commitment over another order of its three parts or a slot without its domain gives other bytes.
        let sl = name_slot("alice").expect("alice is a lawful name");
        assert_eq!(hex(&sl), "b5793a0d4f7f0737ebffb1374d24d3eed05efef5bd63eb1e4b03d81652c2575e");
        let ch = name_chain(&[0xEEu8; 32]);
        assert_eq!(ch.len(), (mt_names::NAME_CHAIN_LEN + 1) * 32);
        let link = |k: usize| -> [u8; 32] { let mut l = [0u8; 32]; l.copy_from_slice(&ch[k * 32..(k + 1) * 32]); l };
        assert_eq!(hex(&link(127)), "83be15d760052903e3b1a2d304f56861ad92b8fed97a0b08452c6eb029fe1b5a");
        assert_eq!(hex(&link(0)), "b49373b194e6358022b8fbcbecb5beccdd4f0b275d1ccd53be130f76a1367a8e");
        assert_eq!(hex(&name_commit(&sl, &[0xDDu8; 32], &link(0))), "929fccf5c511d3d1123707db473cf21732a9349bcb578ddea91ca08b2d9dae41");
        assert!(name_verify_link(&link(0), &link(1)));
        assert!(!name_verify_link(&link(1), &link(0)));   // the proof runs one way
        assert_eq!(hex(&first_tag(&[0xCCu8; 1184], 1000)), "45468cdd9bcdebe6f622c46257c27fe3");
        assert_eq!(hex(&first_tag(&[0xCCu8; 1184], 1001)), "2751a149c51e219b73fadc85ca8b107b");
        // What a person typed is no slot; the sign before a name is no part of it.
        assert!(name_slot("Alice").is_none());
        assert_eq!(name_normalize("@Alice").as_deref(), Some("alice"));
        // A seed of no pattern: this door and the iOS door give one branch and one contact seed.
        let seed: Vec<u8> = (0..64).map(|i| ((i * 13 + 5) % 251) as u8).collect();
        let mut own = [0u8; 32];
        assert_eq!(unsafe { mt_bindings::ffi_names::mt_name_own(seed.as_ptr(), seed.len(), sl.as_ptr(), own.as_mut_ptr()) }, 0);
        assert_eq!(&name_own(&seed, &sl)[..], &own[..]);
        let mut cs = [0u8; 64];
        assert_eq!(unsafe { mt_bindings::ffi_names::mt_name_contact_seed(seed.as_ptr(), seed.len(), sl.as_ptr(), cs.as_mut_ptr()) }, 0);
        assert_eq!(&name_contact_seed(&seed, &sl)[..], &cs[..]);
    }
}
