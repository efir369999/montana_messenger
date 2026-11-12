//! Cross-backend KAT: the pure-Rust ml-dsa (web/wasm backend) and native OpenSSL
//! (mt-crypto) must produce byte-identical keys, account_id and signatures.
//! Catches any backend divergence at build time.
#![cfg(not(target_arch = "wasm32"))]

use ml_dsa::{
    EncodedVerifyingKey, Keypair, MlDsa65, Signature as RcSig, Signer, SigningKey, Verifier,
    VerifyingKey, B32,
};
use mt_messenger_e2e::safety::{party_code, safety_number};
use mt_mnemonic::{entropy_to_mnemonic, mldsa_seed_for_role, mnemonic_to_master_seed};
use sha2::{Digest, Sha256};

fn zero_acc_seed() -> [u8; 32] {
    let mnemonic = entropy_to_mnemonic(&[0u8; 32]);
    let master = mnemonic_to_master_seed(&mnemonic).unwrap();
    mldsa_seed_for_role(&master, mt_codec::domain::ACCOUNT_KEY)
}

#[test]
fn ml_dsa_wasm_backend_matches_openssl_kat() {
    let acc_seed = zero_acc_seed();
    let seed = B32::try_from(&acc_seed[..]).unwrap();
    let sk = SigningKey::<MlDsa65>::from_seed(&seed);
    let pk = sk.verifying_key().encode();
    let mut h = Sha256::new();
    h.update(mt_codec::domain::ACCOUNT);
    h.update([0u8]);
    h.update([0x01u8, 0x00u8]);
    h.update(pk.as_slice());
    let id = hex::encode(h.finalize());
    assert_eq!(
        id,
        "9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21"
    );
}

/// Cross-backend: OpenSSL (mt-crypto) ↔ pure-Rust (ml-dsa) on the same ξ:
/// (1) public keys are byte-identical; (2) signatures are byte-identical
/// (ML-DSA-65 is deterministic, empty context); (3) each backend signature
/// verifies under the other.
#[test]
fn cross_backend_sign_verify() {
    let acc_seed = zero_acc_seed();
    let msg = b"montana cross-backend kat";

    // OpenSSL backend
    let (pk_o, sk_o) = mt_crypto::keypair_from_seed(&acc_seed).unwrap();
    let sig_o = mt_crypto::sign(&sk_o, msg).unwrap();

    // pure-Rust backend
    let seed = B32::try_from(&acc_seed[..]).unwrap();
    let sk_r = SigningKey::<MlDsa65>::from_seed(&seed);
    let pk_r = sk_r.verifying_key();
    let sig_r: RcSig<MlDsa65> = sk_r.sign(msg);
    let sig_r_bytes = sig_r.encode();

    // (1) pubkeys identical
    assert_eq!(&pk_o.as_bytes()[..], pk_r.encode().as_slice());
    // (2) deterministic signatures identical
    assert_eq!(&sig_o.as_bytes()[..], sig_r_bytes.as_slice());

    // (3a) ml-dsa signature verifies under OpenSSL
    let sig_r_as_o = mt_crypto::Signature::from_slice(sig_r_bytes.as_slice()).unwrap();
    assert!(mt_crypto::verify(&pk_o, msg, &sig_r_as_o));

    // (3b) OpenSSL signature verifies under ml-dsa
    let enc = EncodedVerifyingKey::<MlDsa65>::try_from(&pk_o.as_bytes()[..]).unwrap();
    let vk_r = VerifyingKey::<MlDsa65>::decode(&enc);
    let sig_o_as_r = RcSig::<MlDsa65>::try_from(sig_o.as_bytes().as_slice()).unwrap();
    assert!(vk_r.verify(msg, &sig_o_as_r).is_ok());
}

/// Cross-backend ML-KEM + identity-KEM signature: app_kem_pub from the seed is byte-identical
/// (OpenSSL vs ml-kem), app_kem_sig (ML-DSA over "mt-idkem"‖0x00‖app_kem_pub)
/// is valid. Prints SHA-256 fingerprints for the Stage 4 binding vectors.
#[test]
fn cross_backend_app_kem_and_idkem_sig() {
    use ml_kem::{EncodedSizeUser, KemCore, MlKem768, B32 as KemB32};

    let mnemonic = entropy_to_mnemonic(&[0u8; 32]);
    let master = mnemonic_to_master_seed(&mnemonic).unwrap();
    let app_kem_seed =
        mt_mnemonic::mlkem_seed_for_role(&master, mt_codec::domain::APP_ENCRYPTION_KEY);

    // OpenSSL ML-KEM
    let (pk_o, _sk_o) = mt_crypto::keypair_from_seed_mlkem(&app_kem_seed).unwrap();
    // pure-Rust ML-KEM (d = first 32, z = last 32)
    let d = KemB32::try_from(&app_kem_seed[..32]).unwrap();
    let z = KemB32::try_from(&app_kem_seed[32..]).unwrap();
    let (_dk, ek) = MlKem768::generate_deterministic(&d, &z);
    // (1) cross-backend app_kem_pub identical
    assert_eq!(&pk_o.as_bytes()[..], ek.as_bytes().as_slice());

    let app_kem_pub = pk_o.as_bytes();

    // app_kem_sig = ML-DSA sign(account_key, "mt-idkem" || 0x00 || app_kem_pub)
    let acc_seed = zero_acc_seed();
    let (pk_acc, sk_acc) = mt_crypto::keypair_from_seed(&acc_seed).unwrap();
    let mut msg = Vec::with_capacity(8 + 1 + 1184);
    msg.extend_from_slice(b"mt-idkem");
    msg.push(0u8);
    msg.extend_from_slice(app_kem_pub);
    let sig = mt_crypto::sign(&sk_acc, &msg).unwrap();
    // (2) app_kem_sig verifies under account_key
    assert!(mt_crypto::verify(&pk_acc, &msg, &sig));

    // baked Stage 4 binding vectors (zero mnemonic)
    assert_eq!(
        hex::encode(Sha256::digest(app_kem_pub)),
        "b827d37b2b225907c835f25a8652c215af69f8f52bd6a7ef0ae31955d63fd1c4"
    );
    assert_eq!(
        hex::encode(Sha256::digest(sig.as_bytes())),
        "316e908176df3d7e17b5a4cec8d0292ab2f0bdeefa3f51da3eb2bf57df80d595"
    );
}

// ---- Stage 5: PQXDH (pure ML-KEM-768) ----

fn hmac_sha256(key: &[u8], msg: &[u8]) -> [u8; 32] {
    let mut k = [0u8; 64];
    if key.len() > 64 {
        k[..32].copy_from_slice(&Sha256::digest(key));
    } else {
        k[..key.len()].copy_from_slice(key);
    }
    let mut ipad = [0x36u8; 64];
    let mut opad = [0x5cu8; 64];
    for i in 0..64 {
        ipad[i] ^= k[i];
        opad[i] ^= k[i];
    }
    let mut hi = Sha256::new();
    hi.update(ipad);
    hi.update(msg);
    let inner = hi.finalize();
    let mut ho = Sha256::new();
    ho.update(opad);
    ho.update(inner);
    ho.finalize().into()
}

fn hkdf_sha256(salt: &[u8], ikm: &[u8], info: &[u8], l: usize) -> Vec<u8> {
    let prk = hmac_sha256(salt, ikm);
    let mut okm = Vec::new();
    let mut t: Vec<u8> = Vec::new();
    let mut i = 1u8;
    while okm.len() < l {
        let mut m = t.clone();
        m.extend_from_slice(info);
        m.push(i);
        t = hmac_sha256(&prk, &m).to_vec();
        okm.extend_from_slice(&t);
        i += 1;
    }
    okm.truncate(l);
    okm
}

/// Deterministic PQXDH key schedule (Stage 5, Step 3). Fixed
/// secrets + transcript_hash → baked initial_root_key / chain (with and
/// without a one-time key). Pure HKDF-SHA-256 → identical across platforms.
#[test]
fn pqxdh_key_schedule_kat() {
    let ss_id = [0x11u8; 32];
    let ss_spk = [0x22u8; 32];
    let ss_opk = [0x33u8; 32];
    let transcript_hash = [0xAAu8; 32];
    let salt = [0u8; 32];
    let mut info = b"mt-pqxdh-root".to_vec();
    info.push(0u8);
    info.extend_from_slice(&transcript_hash);

    // with one-time key: IKM = ss_id || ss_spk || ss_opk
    let mut ikm = Vec::new();
    ikm.extend_from_slice(&ss_id);
    ikm.extend_from_slice(&ss_spk);
    ikm.extend_from_slice(&ss_opk);
    let okm = hkdf_sha256(&salt, &ikm, &info, 96);
    assert_eq!(
        hex::encode(&okm[..32]),
        "d1d0a8699658a49099eddf5eafa58cf9da1d8ff02ce00f7218245b3bee0efcd1"
    );
    assert_eq!(
        hex::encode(&okm[32..64]),
        "082046319cc79abbfa129a7699607dd55fe989ca9f1822ab5af53692788a27b2"
    );
    assert_eq!(
        hex::encode(&okm[64..96]),
        "872152f9fcef01639bda5890534901b1ed2c206334b64eeb46c62532ffeed5b9"
    );
    let mut ci = b"mt-pqxdh-confirm".to_vec();
    ci.push(0u8);
    ci.extend_from_slice(&transcript_hash);
    assert_eq!(
        hex::encode(hmac_sha256(&okm[64..96], &ci)),
        "6f5d00d0a49c7a231819863706eb93bc859071ee2b7919e9e0db5c58af538dbf"
    );

    // without one-time key: IKM = ss_id || ss_spk
    let mut ikm2 = Vec::new();
    ikm2.extend_from_slice(&ss_id);
    ikm2.extend_from_slice(&ss_spk);
    let okm2 = hkdf_sha256(&salt, &ikm2, &info, 96);
    assert_eq!(
        hex::encode(&okm2[..32]),
        "38fa29cc640c4a87e554ece7cb1168bf3d18bd0e4b6ee5683336091c433ca4ca"
    );
    assert_eq!(
        hex::encode(&okm2[32..64]),
        "6697d2bb86b5306ff82a86e9213655328bde8b3056226f5d3b1c89b769a76098"
    );
    assert_eq!(
        hex::encode(&okm2[64..96]),
        "19defc490566c6523a96b36610ade231fb73ca9418eeaba9d6fa724bf7ff375b"
    );
    assert_eq!(
        hex::encode(hmac_sha256(&okm2[64..96], &ci)),
        "441e93d5283d8af4d053a16a4a3601342fbae0550c501e700d9062ce5d98bf56"
    );
}

/// PQXDH agreement between the parties (Stage 5). Alice encapsulates to three real ML-KEM
/// keys of Bob (OpenSSL), Bob decapsulates -- the shared secrets and the derived root
/// match byte for byte. Exercises the whole session-establishment flow.
#[test]
fn pqxdh_agreement() {
    // Bob's keys
    let mnemonic = entropy_to_mnemonic(&[0u8; 32]);
    let master = mnemonic_to_master_seed(&mnemonic).unwrap();
    let app_seed = mt_mnemonic::mlkem_seed_for_role(&master, mt_codec::domain::APP_ENCRYPTION_KEY);
    let (app_pk, app_sk) = mt_crypto::keypair_from_seed_mlkem(&app_seed).unwrap();
    let (spk_pk, spk_sk) = mt_crypto::keypair_from_seed_mlkem(&[0x55u8; 64]).unwrap();
    let (opk_pk, opk_sk) = mt_crypto::keypair_from_seed_mlkem(&[0x66u8; 64]).unwrap();

    // Alice encapsulates
    let (ct_id, ss_id_a) = mt_crypto::mlkem_encapsulate(&app_pk).unwrap();
    let (ct_spk, ss_spk_a) = mt_crypto::mlkem_encapsulate(&spk_pk).unwrap();
    let (ct_opk, ss_opk_a) = mt_crypto::mlkem_encapsulate(&opk_pk).unwrap();

    // Bob decapsulates
    let ss_id_b = mt_crypto::mlkem_decapsulate(&app_sk, &ct_id).unwrap();
    let ss_spk_b = mt_crypto::mlkem_decapsulate(&spk_sk, &ct_spk).unwrap();
    let ss_opk_b = mt_crypto::mlkem_decapsulate(&opk_sk, &ct_opk).unwrap();

    assert_eq!(ss_id_a.as_bytes(), ss_id_b.as_bytes());
    assert_eq!(ss_spk_a.as_bytes(), ss_spk_b.as_bytes());
    assert_eq!(ss_opk_a.as_bytes(), ss_opk_b.as_bytes());

    // both sides: the same key schedule → equal root
    let salt = [0u8; 32];
    let mut info = b"mt-pqxdh-root".to_vec();
    info.push(0u8);
    info.extend_from_slice(&[0xCCu8; 32]); // fixed transcript_hash (the same on both sides)

    let ikm = |a: &[u8; 32], b: &[u8; 32], c: &[u8; 32]| {
        let mut v = Vec::new();
        v.extend_from_slice(a);
        v.extend_from_slice(b);
        v.extend_from_slice(c);
        v
    };
    let root_a = hkdf_sha256(
        &salt,
        &ikm(ss_id_a.as_bytes(), ss_spk_a.as_bytes(), ss_opk_a.as_bytes()),
        &info,
        64,
    );
    let root_b = hkdf_sha256(
        &salt,
        &ikm(ss_id_b.as_bytes(), ss_spk_b.as_bytes(), ss_opk_b.as_bytes()),
        &info,
        64,
    );
    assert_eq!(root_a, root_b);
    assert_eq!(root_a.len(), 64);
}

// ---- Stage 6: double ratchet ----

fn kdf_ck(ck: &[u8; 32]) -> ([u8; 32], [u8; 32]) {
    (hmac_sha256(ck, &[0x01]), hmac_sha256(ck, &[0x02]))
}

#[test]
fn ratchet_aead_kat() {
    let mk = kdf_ck(&[0x42u8; 32]).0;
    let (enc_key, nonce) = msg_key(&mk);
    assert_eq!(
        hex::encode(enc_key),
        "7bb31482d13db3ad12d8529dc53aa5ba4f47b490b29f13fa275d6f56de4e8ed4"
    );
    assert_eq!(hex::encode(nonce), "00f4b713e2453c6ace58189c");
    let mut ad = vec![0xAAu8; 32];
    ad.extend_from_slice(&0u32.to_le_bytes());
    ad.extend_from_slice(&0u32.to_le_bytes());
    ad.extend_from_slice(&[0x07u8; 1184]);
    let body = seal(&enc_key, &nonce, b"montana", &ad);
    assert_eq!(
        hex::encode(&body),
        "5f43ddbc831a09fab69467ec81e97c2b10e2ba06b1f287"
    );
    assert_eq!(open(&enc_key, &nonce, &body, &ad).unwrap(), b"montana");
}

fn kdf_rk(rk: &[u8; 32], ss: &[u8; 32]) -> ([u8; 32], [u8; 32]) {
    let okm = hkdf_sha256(rk, ss, b"mt-ratchet-rk", 64);
    let mut a = [0u8; 32];
    let mut b = [0u8; 32];
    a.copy_from_slice(&okm[..32]);
    b.copy_from_slice(&okm[32..]);
    (a, b)
}

fn msg_key(mk: &[u8; 32]) -> ([u8; 32], [u8; 12]) {
    let okm = hkdf_sha256(&[0u8; 32], mk, b"mt-ratchet-msg", 44);
    let mut k = [0u8; 32];
    let mut n = [0u8; 12];
    k.copy_from_slice(&okm[..32]);
    n.copy_from_slice(&okm[32..44]);
    (k, n)
}

fn ad_bytes(sid: &[u8; 32], pn: u32, ns: u32, rpub: &[u8; 1184]) -> Vec<u8> {
    let mut ad = Vec::with_capacity(32 + 8 + 1184);
    ad.extend_from_slice(sid);
    ad.extend_from_slice(&pn.to_le_bytes());
    ad.extend_from_slice(&ns.to_le_bytes());
    ad.extend_from_slice(rpub);
    ad
}

fn seal(k: &[u8; 32], n: &[u8; 12], pt: &[u8], ad: &[u8]) -> Vec<u8> {
    use chacha20poly1305::aead::{Aead, Payload};
    use chacha20poly1305::{ChaCha20Poly1305, KeyInit, Nonce};
    ChaCha20Poly1305::new_from_slice(k)
        .unwrap()
        .encrypt(Nonce::from_slice(n), Payload { msg: pt, aad: ad })
        .unwrap()
}

fn open(k: &[u8; 32], n: &[u8; 12], ctb: &[u8], ad: &[u8]) -> Option<Vec<u8>> {
    use chacha20poly1305::aead::{Aead, Payload};
    use chacha20poly1305::{ChaCha20Poly1305, KeyInit, Nonce};
    ChaCha20Poly1305::new_from_slice(k)
        .unwrap()
        .decrypt(Nonce::from_slice(n), Payload { msg: ctb, aad: ad })
        .ok()
}

#[test]
fn ratchet_kdf_kat() {
    let (mk, ckn) = kdf_ck(&[0x42u8; 32]);
    assert_eq!(
        hex::encode(mk),
        "0b175bca3524cc7301c33946d7e00d3f008cb14632b72855b3442a7365403893"
    );
    assert_eq!(
        hex::encode(ckn),
        "4fa923f5d122080142716bf80fec4930203815c6b10199d1a871e09fe0a3c720"
    );
    let (rkn, ck) = kdf_rk(&[0x01u8; 32], &[0x02u8; 32]);
    assert_eq!(
        hex::encode(rkn),
        "37e663dfa28c8d5f87228aec91eb191a0536f5348254bc47a0617e3a0f4af9d5"
    );
    assert_eq!(
        hex::encode(ck),
        "1b0350c65ad26f14bb52e21d8b3f73c778b17f4efa7d9d096f7d18e5ef4fb3bb"
    );
}

type KemKp = (mt_crypto::MlkemPublicKey, mt_crypto::MlkemSecretKey);
type SkipEntry = (([u8; 1184], u32), [u8; 32]);

struct Msg {
    ratchet_pub: [u8; 1184],
    ct: Option<[u8; 1088]>,
    pn: u32,
    ns: u32,
    body: Vec<u8>,
}

struct Rat {
    sid: [u8; 32],
    rk: [u8; 32],
    dhs: KemKp,
    dhr: Option<mt_crypto::MlkemPublicKey>,
    cks: Option<[u8; 32]>,
    ckr: Option<[u8; 32]>,
    send_ct: Option<[u8; 1088]>,
    ns: u32,
    nr: u32,
    pn: u32,
    skipped: Vec<SkipEntry>,
    pending: bool,
    seed_base: u8,
    seed_ctr: u8,
}

impl Rat {
    fn new_kp(&mut self) -> KemKp {
        let mut seed = [self.seed_base; 64];
        seed[0] = self.seed_ctr;
        self.seed_ctr = self.seed_ctr.wrapping_add(1);
        mt_crypto::keypair_from_seed_mlkem(&seed).unwrap()
    }
}

fn encrypt(r: &mut Rat, pt: &[u8]) -> Msg {
    if r.pending {
        r.pn = r.ns;
        r.ns = 0;
        let (pk, sk) = r.new_kp();
        let (ct, ss) = mt_crypto::mlkem_encapsulate(r.dhr.as_ref().unwrap()).unwrap();
        let (rk2, ck) = kdf_rk(&r.rk, ss.as_bytes());
        r.rk = rk2;
        r.cks = Some(ck);
        r.send_ct = Some(*ct.as_bytes());
        r.dhs = (pk, sk);
        r.pending = false;
    }
    let (mk, ck2) = kdf_ck(&r.cks.unwrap());
    r.cks = Some(ck2);
    let (ek, no) = msg_key(&mk);
    let rpub = *r.dhs.0.as_bytes();
    let ad = ad_bytes(&r.sid, r.pn, r.ns, &rpub);
    let body = seal(&ek, &no, pt, &ad);
    let m = Msg {
        ratchet_pub: rpub,
        ct: r.send_ct,
        pn: r.pn,
        ns: r.ns,
        body,
    };
    r.ns += 1;
    m
}

fn decrypt(r: &mut Rat, m: &Msg) -> Option<Vec<u8>> {
    if let Some(pos) = r
        .skipped
        .iter()
        .position(|((rp, n), _)| *rp == m.ratchet_pub && *n == m.ns)
    {
        let mk = r.skipped.remove(pos).1;
        let (ek, no) = msg_key(&mk);
        let ad = ad_bytes(&r.sid, m.pn, m.ns, &m.ratchet_pub);
        return open(&ek, &no, &m.body, &ad);
    }
    let is_step = match &r.dhr {
        Some(d) => d.as_bytes() != &m.ratchet_pub,
        None => true,
    };
    let mut rk = r.rk;
    let mut ckr = r.ckr;
    let mut nr = r.nr;
    let mut dhr_bytes: Option<[u8; 1184]> = r.dhr.as_ref().map(|d| *d.as_bytes());
    let mut new_skipped: Vec<SkipEntry> = Vec::new();
    if is_step {
        let ct = m.ct?;
        if let (Some(cur), Some(mut c)) = (dhr_bytes, ckr) {
            while nr < m.pn {
                let (mk, cn) = kdf_ck(&c);
                new_skipped.push(((cur, nr), mk));
                c = cn;
                nr += 1;
            }
        }
        let ss =
            mt_crypto::mlkem_decapsulate(&r.dhs.1, &mt_crypto::MlkemCiphertext::from_array(ct))
                .unwrap();
        let (rk2, ck) = kdf_rk(&rk, ss.as_bytes());
        rk = rk2;
        ckr = Some(ck);
        dhr_bytes = Some(m.ratchet_pub);
        nr = 0;
    }
    let cur = dhr_bytes.unwrap();
    let mut c = ckr.unwrap();
    while nr < m.ns {
        let (mk, cn) = kdf_ck(&c);
        new_skipped.push(((cur, nr), mk));
        c = cn;
        nr += 1;
    }
    let (mk, cn) = kdf_ck(&c);
    c = cn;
    nr += 1;
    let (ek, no) = msg_key(&mk);
    let ad = ad_bytes(&r.sid, m.pn, m.ns, &m.ratchet_pub);
    let pt = open(&ek, &no, &m.body, &ad)?;
    r.rk = rk;
    r.ckr = Some(c);
    r.nr = nr;
    if is_step {
        r.dhr = Some(mt_crypto::MlkemPublicKey::from_array(m.ratchet_pub));
        r.pending = true;
    }
    r.skipped.extend(new_skipped);
    Some(pt)
}

/// Full double-ratchet flow: two symmetric messages, a reply with a KEM step
/// (real ML-KEM Encaps/Decaps), out-of-order delivery via MKSKIPPED.
#[test]
fn ratchet_session_roundtrip() {
    let sid = [0xABu8; 32];
    let rk0 = [0x01u8; 32];
    let init_chain = [0x02u8; 32];
    let (eph_pub, eph_sk) = mt_crypto::keypair_from_seed_mlkem(&[0x99u8; 64]).unwrap();
    let (spk_pub, spk_sk) = mt_crypto::keypair_from_seed_mlkem(&[0x55u8; 64]).unwrap();
    let eph_pub_bytes = *eph_pub.as_bytes();
    let spk_pub_bytes = *spk_pub.as_bytes();

    let mut alice = Rat {
        sid,
        rk: rk0,
        dhs: (eph_pub, eph_sk),
        dhr: Some(mt_crypto::MlkemPublicKey::from_array(spk_pub_bytes)),
        cks: Some(init_chain),
        ckr: None,
        send_ct: None,
        ns: 0,
        nr: 0,
        pn: 0,
        skipped: Vec::new(),
        pending: false,
        seed_base: 0xA0,
        seed_ctr: 0,
    };
    let mut bob = Rat {
        sid,
        rk: rk0,
        dhs: (spk_pub, spk_sk),
        dhr: Some(mt_crypto::MlkemPublicKey::from_array(eph_pub_bytes)),
        cks: None,
        ckr: Some(init_chain),
        send_ct: None,
        ns: 0,
        nr: 0,
        pn: 0,
        skipped: Vec::new(),
        pending: true,
        seed_base: 0xB0,
        seed_ctr: 0,
    };

    // symmetric ratchet Alice -> Bob
    let m1 = encrypt(&mut alice, b"m1");
    assert_eq!(decrypt(&mut bob, &m1).unwrap(), b"m1");
    let m2 = encrypt(&mut alice, b"m2");
    assert_eq!(decrypt(&mut bob, &m2).unwrap(), b"m2");

    // KEM step: Bob's reply
    let r1 = encrypt(&mut bob, b"r1");
    assert!(r1.ct.is_some());
    assert_eq!(decrypt(&mut alice, &r1).unwrap(), b"r1");

    // Alice takes her own KEM step, two messages, out-of-order delivery (m4 before m3)
    let m3 = encrypt(&mut alice, b"m3");
    let m4 = encrypt(&mut alice, b"m4");
    assert!(m3.ct.is_some() && m4.ct.is_some()); // ct repeats along the chain
    assert_eq!(decrypt(&mut bob, &m4).unwrap(), b"m4");
    assert_eq!(decrypt(&mut bob, &m3).unwrap(), b"m3"); // from MKSKIPPED
}

#[test]
fn seal_kat() {
    let ss_seal = [0x44u8; 32];
    let okm = hkdf_sha256(&[0u8; 32], &ss_seal, b"mt-seal", 44);
    let (mut k, mut n) = ([0u8; 32], [0u8; 12]);
    k.copy_from_slice(&okm[..32]);
    n.copy_from_slice(&okm[32..44]);
    assert_eq!(
        hex::encode(k),
        "5f9f4ccf25e7ba4921c0bc004406af5b743c49783a5989bf185c58844c8d6e5b"
    );
    assert_eq!(hex::encode(n), "02b49c7b9e94ca37b1aed2ac");
    let acc =
        hex::decode("9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21").unwrap();
    let mut ad = b"mt-seal".to_vec();
    ad.push(0u8);
    ad.extend_from_slice(&acc);
    let body = seal(&k, &n, b"handshake", &ad);
    assert_eq!(
        hex::encode(&body),
        "488b64548e48d192e145fc04ae32ceb07c991c959a05c6b594"
    );
    assert_eq!(open(&k, &n, &body, &ad).unwrap(), b"handshake");
}

/// Stage 7 routing labels: routing_secret, directional session labels, inbox label.
#[test]
fn route_label_kat() {
    // routing_secret is derived from the forward-secret initial_root_key (Stage 7), NOT from session_id/transcript_hash
    let initial_root_key = [0xABu8; 32];
    let rs = hkdf_sha256(&[0u8; 32], &initial_root_key, b"mt-routing", 32);
    assert_eq!(
        hex::encode(&rs),
        "5dde1ca30d45f658626b6acfac59f25b39bfc8cbbf9db4250fd60ceb4f6624d1"
    );
    let w: u64 = 1000;
    let label = |dir: u8| {
        let mut m = b"mt-label".to_vec();
        m.push(0u8);
        m.push(dir);
        m.extend_from_slice(&w.to_le_bytes());
        hex::encode(&hmac_sha256(&rs, &m)[..16])
    };
    assert_eq!(label(0x00), "bb4ca49fe117ff008b3f959f19ec186b");
    assert_eq!(label(0x01), "1b4bc34a8901e9cef430c077f9b19d54");
    let acc =
        hex::decode("9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21").unwrap();
    // the inbox label is STABLE (no W): it gives wake-push, rotation gave no privacy
    let mut ib = b"mt-inbox".to_vec();
    ib.push(0u8);
    ib.extend_from_slice(&acc);
    assert_eq!(
        hex::encode(&Sha256::digest(&ib)[..16]),
        "7d5db70fa1b5f7e7902bba6bbbd626ba"
    );
}

/// Stage 7 proof-of-time: seed is bound to the whole envelope; chain y0=H(seed), y_{i+1}=H(y_i).
/// Short-step vector (STEPS=4) pins the seed FORMAT and the iteration (production INBOX_POT_STEPS=2^20).
#[test]
fn pot_chain_kat() {
    let ib = hex::decode("7d5db70fa1b5f7e7902bba6bbbd626ba").unwrap(); // inbox_label 16 B
    let item_id = [0x44u8; 16];
    let delete_commitment = [0x55u8; 32];
    let ct_seal = [0x66u8; 1088];
    let sealed = [0x77u8; 64];
    let mut seed = b"mt-pot".to_vec();
    seed.push(0u8);
    seed.extend_from_slice(&ib);
    seed.extend_from_slice(&item_id);
    seed.extend_from_slice(&delete_commitment);
    seed.extend_from_slice(&ct_seal);
    seed.extend_from_slice(&sealed);
    let mut y = Sha256::digest(&seed).to_vec(); // y0
    for _ in 0..4u32 {
        y = Sha256::digest(&y).to_vec();
    }
    assert_eq!(
        hex::encode(&y),
        "ed47bd474d18e22ef2ff96811fa08c26193e9ac597515be2d96920f72de0a17f"
    );
}

/// Stage 10 history backup: history_key = HKDF(0x32, vault_key, "mt-history-key", 32).
#[test]
fn history_key_kat() {
    let vault_key = [0x55u8; 32];
    let hk = hkdf_sha256(&[0u8; 32], &vault_key, b"mt-history-key", 32);
    assert_eq!(
        hex::encode(&hk),
        "e6a7dc51003770589d9f731c1231c1523be7348c7769383875dd34bd6c578def"
    );
}

/// First-contact sealing end to end: real ML-KEM Encaps/Decaps → shared ss_seal
/// → shared seal_key; Seal then Open recovers the plaintext.
#[test]
fn seal_roundtrip() {
    let (pk, sk) = mt_crypto::keypair_from_seed_mlkem(&[0x77u8; 64]).unwrap();
    let (ct, ss_a) = mt_crypto::mlkem_encapsulate(&pk).unwrap();
    let ss_b = mt_crypto::mlkem_decapsulate(&sk, &ct).unwrap();
    assert_eq!(ss_a.as_bytes(), ss_b.as_bytes());

    let derive = |ss: &[u8; 32]| {
        let okm = hkdf_sha256(&[0u8; 32], ss, b"mt-seal", 44);
        let (mut k, mut n) = ([0u8; 32], [0u8; 12]);
        k.copy_from_slice(&okm[..32]);
        n.copy_from_slice(&okm[32..44]);
        (k, n)
    };
    let (ka, na) = derive(ss_a.as_bytes());
    let (kb, nb) = derive(ss_b.as_bytes());
    let ad = b"mt-seal\x00route-e2e";
    let sealed = seal(&ka, &na, b"InitialHandshake", ad);
    assert_eq!(open(&kb, &nb, &sealed, ad).unwrap(), b"InitialHandshake");
}

fn frame(t: u8, body: &[u8]) -> Vec<u8> {
    let mut fb = vec![t];
    fb.extend_from_slice(body);
    let mut out = (fb.len() as u32).to_le_bytes().to_vec();
    out.extend_from_slice(&fb);
    out
}

/// Stage 7: WebSocket frame codec for blind delivery (frame_len u32 LE + type + body).
#[test]
fn frame_codec_kat() {
    let mut sub = 1u16.to_le_bytes().to_vec();
    sub.extend_from_slice(&[0x11u8; 16]);
    assert_eq!(
        hex::encode(frame(0x01, &sub)),
        "1300000001010011111111111111111111111111111111"
    );
    // DELIVER: label + window + item_id + delete_commitment(32) + ct (E1)
    let mut del = [0x22u8; 16].to_vec();
    del.extend_from_slice(&1000u64.to_le_bytes());
    del.extend_from_slice(&[0x44u8; 16]); // item_id
    del.extend_from_slice(&[0x55u8; 32]); // delete_commitment
    del.extend_from_slice(b"hi");
    assert_eq!(
        hex::encode(frame(0x04, &del)),
        "4b0000000422222222222222222222222222222222e8030000000000004444444444444444444444444444444455555555555555555555555555555555555555555555555555555555555555556869"
    );
    // ACK: count + (label + item_id + delete_preimage(32)) (E1)
    let mut ack = 1u16.to_le_bytes().to_vec();
    ack.extend_from_slice(&[0x33u8; 16]); // label
    ack.extend_from_slice(&[0x44u8; 16]); // item_id
    ack.extend_from_slice(&[0x66u8; 32]); // delete_preimage
    assert_eq!(
        hex::encode(frame(0x05, &ack)),
        "4300000005010033333333333333333333333333333333444444444444444444444444444444446666666666666666666666666666666666666666666666666666666666666666"
    );
}

/// Stage 8: per-identity code and pairwise fingerprint (iterated SHA-256, ITER=5200).
#[test]
fn safety_number_kat() {
    let a: [u8; 32] =
        hex::decode("9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21")
            .unwrap()
            .try_into()
            .unwrap();
    let b = [0x11u8; 32];
    assert_eq!(party_code(&a), "157809020367483198118535796002");
    assert_eq!(party_code(&b), "534333257869110355393448740858");
    assert_eq!(
        safety_number(&a, &b),
        "534333257869110355393448740858157809020367483198118535796002"
    );
}

use mt_messenger_e2e::content::{encode_receipt as content_receipt, encode_text as content_text};

fn content_typing(msg_id: &[u8; 16], sent_at: u64, state: u8) -> Vec<u8> {
    mt_messenger_e2e::content::encode_typing(msg_id, sent_at, state == 1)
}

/// Stage 9: content codec (ratchet plaintext) -- text / delivery_receipt / typing.
#[test]
fn content_codec_kat() {
    assert_eq!(
        hex::encode(content_text(&[0x11; 16], 1000, &[0u8; 16], b"hi")),
        "0111111111111111111111111111111111e80300000000000000000000000000000000000000000000020000006869"
    );
    assert_eq!(
        hex::encode(content_receipt(0x02, &[0x22; 16], 2000, &[0x11; 16])),
        "0222222222222222222222222222222222d00700000000000011111111111111111111111111111111"
    );
    assert_eq!(
        hex::encode(content_typing(&[0x33; 16], 3000, 0x01)),
        "0433333333333333333333333333333333b80b00000000000001"
    );
}

/// Stage 10: canonical byte layout of the signed DeviceRegistry (registry_seq rollback protection).
#[test]
fn device_registry_kat() {
    use mt_messenger_e2e::device_registry::{
        encode_entry, registry_sign_message, DeviceEntry, ENTRY_LEN,
    };
    let entry = DeviceEntry {
        device_id: [0x11; 16],
        device_kem_pub: [0x77; 1184],
        added_at: 1000,
        revoked: false,
    };
    assert_eq!(encode_entry(&entry).len(), ENTRY_LEN);
    let msg = registry_sign_message(5, 2000, &[entry]);
    assert_eq!(msg.len(), 1247);
    assert_eq!(
        hex::encode(Sha256::digest(&msg)),
        "d32761561a28a29b68125de252c05c9f529185fd7d5182863b4bbc0720a3e863"
    );
}

/// Stage 11: signing message of an @name claim.
#[test]
fn username_claim_kat() {
    let acc: [u8; 32] =
        hex::decode("9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21")
            .unwrap()
            .try_into()
            .unwrap();
    let msg = mt_messenger_e2e::contacts::username_claim_message(b"alice", &acc);
    assert_eq!(msg.len(), 49);
    assert_eq!(
        hex::encode(Sha256::digest(&msg)),
        "3dd4fd698cb00f19ee52888af860e14d48bc50674c77e01e576cf024161021b6"
    );
}

/// Stage 11: canonical ContactRecord layout (private, encrypted in the vault).
#[test]
fn contact_record_kat() {
    let acc: [u8; 32] =
        hex::decode("9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21")
            .unwrap()
            .try_into()
            .unwrap();
    let rec = mt_messenger_e2e::contacts::encode_contact_record(
        &mt_messenger_e2e::contacts::ContactRecord {
            account_id: acc,
            verified: true,
            username: b"alice".to_vec(),
            display_name: b"Alice".to_vec(),
            added_at: 1000,
        },
    );
    assert_eq!(rec.len(), 53);
    assert_eq!(
        hex::encode(&rec),
        "9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a210105616c69636505416c696365e803000000000000"
    );
}

/// Stage 11: separate contacts encryption key (from the entropy_32 seed, separate domain).
#[test]
fn contacts_key_kat() {
    let ck = mt_messenger_e2e::contacts::contacts_key(&[0x55u8; 32]);
    assert_eq!(
        hex::encode(ck),
        "8a341c252f20b83f33ba2471fd915b11bed788c0b23f205cf8ce3a4de2c65301"
    );
}

#[test]
fn media_blob_kat() {
    let blob_key = [0x66u8; 32];
    let nonce = [0u8; 12];
    let sealed_body = seal(&blob_key, &nonce, b"montana-media", b"mt-media\x00");
    assert_eq!(
        hex::encode(&sealed_body),
        "e26a877f209a12646c4e630e0a6705598d68389e621357aee335b7d636"
    );
    let mut sealed_blob = nonce.to_vec();
    sealed_blob.extend_from_slice(&sealed_body);
    assert_eq!(
        hex::encode(Sha256::digest(&sealed_blob)),
        "6c385ae2ef1c472b373a77e582c889d7ed2585c5a036c246b580f05f94c7efd3"
    );
}

/// Stage 12: canonical layout of media Content (type 0x05, blob reference).
#[test]
fn media_content_kat() {
    let blob_id =
        hex::decode("6c385ae2ef1c472b373a77e582c889d7ed2585c5a036c246b580f05f94c7efd3").unwrap();
    let mut c = vec![0x05u8];
    c.extend_from_slice(&[0x11u8; 16]); // msg_id
    c.extend_from_slice(&1000u64.to_le_bytes()); // sent_at
    c.push(0x01); // media_kind image
    c.extend_from_slice(&blob_id);
    c.extend_from_slice(&[0x66u8; 32]); // blob_key
    c.extend_from_slice(&13u64.to_le_bytes()); // size
    c.push(9);
    c.extend_from_slice(b"image/png");
    c.push(5);
    c.extend_from_slice(b"a.png");
    c.extend_from_slice(&0u16.to_le_bytes()); // thumb_len
    assert_eq!(c.len(), 116);
    assert_eq!(
        hex::encode(&c),
        "0511111111111111111111111111111111e803000000000000016c385ae2ef1c472b373a77e582c889d7ed2585c5a036c246b580f05f94c7efd366666666666666666666666666666666666666666666666666666666666666660d0000000000000009696d6167652f706e6705612e706e670000"
    );
}

/// Stage 7 (E1): deletion commitment = SHA-256(delete_preimage).
#[test]
fn call_key_kat() {
    let ck = mt_messenger_e2e::call::call_key(&[0x44u8; 32]);
    assert_eq!(
        hex::encode(ck),
        "c0a443e76155b699d691a3902eedc5c0f43ec860a28b57f6ca70633fc1d99bde"
    );
    assert_eq!(
        hex::encode(mt_messenger_e2e::call::sframe_key(&ck)),
        "5a23f3dfbad643d36fddf3c2d415371c0532a5a5640c514c061d94c1a47e3d84"
    );
}

#[test]
fn delete_commitment_kat() {
    assert_eq!(
        hex::encode(Sha256::digest([0x77u8; 32])),
        "e29442e61ad354e5cb0831e2e8359e8fb50cf024ad5a8f407c8f9de63bdf7371"
    );
}
