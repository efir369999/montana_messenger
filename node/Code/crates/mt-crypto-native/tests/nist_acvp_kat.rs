// NIST ACVP-Server KAT cross-check для ML-DSA-65 + ML-KEM-768.
//
// Источник fixtures: https://github.com/usnistgov/ACVP-Server
// (Apache-2.0 licensed, public domain test vectors из NIST CAVP).
//
// Закрывает [C-6] Req #11 (preventive NIST KAT в Phase 1) + Req #13
// (differential testing mandatory) для consensus-critical KeyGen path.
//
// Критерий conformance: байт-в-байт совпадение output OpenSSL 3.5.5 LTS
// (наш backend) с NIST published expected values на seed inputs из
// FIPS 204 Algorithm 1 (ML-DSA KeyGen_internal) и FIPS 203 Algorithm
// 16 (ML-KEM KeyGen_internal).
//
// Закрывает F-3 audit finding M1-F (KAT-baselines self-derived без
// independent oracle).

use mt_crypto_native::{
    mt_keypair_from_seed_mldsa, mt_keypair_from_seed_mlkem, mt_mlkem_decapsulate, mt_sign_mldsa,
    mt_sign_mldsa_ctx, MLDSA65_PUBKEY_SIZE, MLDSA65_SECRETKEY_SIZE, MLDSA65_SEED_SIZE,
    MLDSA65_SIGNATURE_SIZE, MLKEM768_CIPHERTEXT_SIZE, MLKEM768_PUBKEY_SIZE,
    MLKEM768_SECRETKEY_SIZE, MLKEM768_SEED_SIZE, MT_OK,
};
use serde::Deserialize;
use std::fs;
use std::path::PathBuf;

fn fixture_path(name: &str) -> PathBuf {
    let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.push("tests");
    p.push("fixtures");
    p.push("nist_acvp");
    p.push(name);
    p
}

fn hex_decode(s: &str) -> Vec<u8> {
    let s = s.trim();
    assert!(
        s.len() % 2 == 0,
        "hex string must have even length: {}",
        s.len()
    );
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).expect("invalid hex"))
        .collect()
}

#[derive(Deserialize)]
struct MlDsaKeyGenFile {
    source: String,
    algorithm: String,
    mode: String,
    tests: Vec<MlDsaKeyGenTest>,
}

#[derive(Deserialize)]
struct MlDsaKeyGenTest {
    #[serde(rename = "tcId")]
    tc_id: u32,
    seed: String,
    pk: String,
    sk: String,
}

#[derive(Deserialize)]
struct MlKemKeyGenFile {
    source: String,
    algorithm: String,
    mode: String,
    tests: Vec<MlKemKeyGenTest>,
}

#[derive(Deserialize)]
struct MlKemKeyGenTest {
    #[serde(rename = "tcId")]
    tc_id: u32,
    d: String,
    z: String,
    ek: String,
    dk: String,
}

#[derive(Deserialize)]
struct MlDsaSigGenFile {
    source: String,
    algorithm: String,
    mode: String,
    tests: Vec<MlDsaSigGenTest>,
}

#[derive(Deserialize)]
struct MlDsaSigGenTest {
    #[serde(rename = "tcId")]
    tc_id: u32,
    sk: String,
    message: String,
    context: String,
    signature: String,
}

#[test]
fn nist_acvp_ml_dsa_65_keygen_byte_exact() {
    let path = fixture_path("ml_dsa_65_keygen.json");
    let raw = fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("read fixture {}: {}", path.display(), e));
    let kat: MlDsaKeyGenFile = serde_json::from_str(&raw).expect("parse ml_dsa_65_keygen.json");
    assert_eq!(kat.algorithm, "ML-DSA-65");
    assert_eq!(kat.mode, "KeyGen");
    assert!(!kat.tests.is_empty(), "no tests in fixture");
    println!(
        "NIST ACVP ML-DSA-65 KeyGen — {} tests from: {}",
        kat.tests.len(),
        kat.source
    );

    let mut passed = 0u32;
    for t in &kat.tests {
        let seed_bytes = hex_decode(&t.seed);
        assert_eq!(
            seed_bytes.len(),
            MLDSA65_SEED_SIZE,
            "tcId={} seed wrong length",
            t.tc_id
        );
        let expected_pk = hex_decode(&t.pk);
        let expected_sk = hex_decode(&t.sk);
        assert_eq!(expected_pk.len(), MLDSA65_PUBKEY_SIZE);
        assert_eq!(expected_sk.len(), MLDSA65_SECRETKEY_SIZE);

        let mut pk = vec![0u8; MLDSA65_PUBKEY_SIZE];
        let mut sk = vec![0u8; MLDSA65_SECRETKEY_SIZE];
        let rc = unsafe {
            mt_keypair_from_seed_mldsa(seed_bytes.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr())
        };
        assert_eq!(
            rc, MT_OK,
            "tcId={} mt_keypair_from_seed_mldsa failed: {}",
            t.tc_id, rc
        );

        assert_eq!(
            pk, expected_pk,
            "tcId={} ML-DSA-65 pubkey diverges from NIST FIPS 204 expected",
            t.tc_id
        );
        assert_eq!(
            sk, expected_sk,
            "tcId={} ML-DSA-65 secretkey diverges from NIST FIPS 204 expected",
            t.tc_id
        );
        passed += 1;
    }
    println!(
        "PASS: {}/{} ML-DSA-65 KeyGen NIST KAT byte-exact",
        passed,
        kat.tests.len()
    );
}

#[test]
fn nist_acvp_ml_kem_768_keygen_byte_exact() {
    let path = fixture_path("ml_kem_768_keygen.json");
    let raw = fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("read fixture {}: {}", path.display(), e));
    let kat: MlKemKeyGenFile = serde_json::from_str(&raw).expect("parse ml_kem_768_keygen.json");
    assert_eq!(kat.algorithm, "ML-KEM-768");
    assert_eq!(kat.mode, "KeyGen");
    assert!(!kat.tests.is_empty(), "no tests in fixture");
    println!(
        "NIST ACVP ML-KEM-768 KeyGen — {} tests from: {}",
        kat.tests.len(),
        kat.source
    );

    let mut passed = 0u32;
    for t in &kat.tests {
        let d_bytes = hex_decode(&t.d);
        let z_bytes = hex_decode(&t.z);
        assert_eq!(d_bytes.len(), 32, "tcId={} d wrong length", t.tc_id);
        assert_eq!(z_bytes.len(), 32, "tcId={} z wrong length", t.tc_id);

        // FIPS 203 §6.1: ML-KEM.KeyGen_internal принимает (d, z) → seed = d || z.
        // OpenSSL OSSL_PKEY_PARAM_ML_KEM_SEED ожидает 64-байтовый seed
        // в этом порядке (d первым, z вторым).
        let mut seed = [0u8; MLKEM768_SEED_SIZE];
        seed[..32].copy_from_slice(&d_bytes);
        seed[32..].copy_from_slice(&z_bytes);

        let expected_ek = hex_decode(&t.ek);
        let expected_dk = hex_decode(&t.dk);
        assert_eq!(expected_ek.len(), MLKEM768_PUBKEY_SIZE);
        assert_eq!(expected_dk.len(), MLKEM768_SECRETKEY_SIZE);

        let mut pk = vec![0u8; MLKEM768_PUBKEY_SIZE];
        let mut sk = vec![0u8; MLKEM768_SECRETKEY_SIZE];
        let rc =
            unsafe { mt_keypair_from_seed_mlkem(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) };
        assert_eq!(
            rc, MT_OK,
            "tcId={} mt_keypair_from_seed_mlkem failed: {}",
            t.tc_id, rc
        );

        assert_eq!(
            pk, expected_ek,
            "tcId={} ML-KEM-768 ek (pubkey) diverges from NIST FIPS 203 expected",
            t.tc_id
        );
        assert_eq!(
            sk, expected_dk,
            "tcId={} ML-KEM-768 dk (secretkey) diverges from NIST FIPS 203 expected",
            t.tc_id
        );
        passed += 1;
    }
    println!(
        "PASS: {}/{} ML-KEM-768 KeyGen NIST KAT byte-exact",
        passed,
        kat.tests.len()
    );
}

#[test]
fn nist_acvp_ml_dsa_65_siggen_deterministic_external_pure_all15() {
    // Deterministic ML-DSA-65 Sign per FIPS 204 Algorithm 2 (deterministic
    // variant). External interface, no preHash, **все 15 cases** (1 empty
    // context + 14 non-empty context, 0..255 байт) tgId=3 в NIST CAVP
    // ML-DSA-sigGen-FIPS204.
    //
    // Использует mt_sign_mldsa_ctx (новая API с context parameter) для
    // полного покрытия SigGen NIST KAT. Empty context case также проходит
    // через mt_sign_mldsa_ctx с ctx_len=0 — equivalent к старому
    // mt_sign_mldsa (cross-verified в `siggen_empty_ctx_equivalence` тесте
    // ниже).
    let path = fixture_path("ml_dsa_65_siggen_det_external_pure_all15.json");
    let raw = fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("read fixture {}: {}", path.display(), e));
    let kat: MlDsaSigGenFile = serde_json::from_str(&raw).expect("parse all15");
    assert!(kat.algorithm.starts_with("ML-DSA-65"));
    assert!(kat.mode.contains("SigGen"));
    assert!(!kat.tests.is_empty(), "no tests in fixture");
    println!(
        "NIST ACVP ML-DSA-65 SigGen (deterministic, external, pure) — {} tests from: {}",
        kat.tests.len(),
        kat.source
    );

    for t in &kat.tests {
        let sk_bytes = hex_decode(&t.sk);
        assert_eq!(sk_bytes.len(), MLDSA65_SECRETKEY_SIZE);
        let msg_bytes = hex_decode(&t.message);
        let ctx_bytes = hex_decode(&t.context);
        let expected_sig = hex_decode(&t.signature);
        assert_eq!(expected_sig.len(), MLDSA65_SIGNATURE_SIZE);

        let mut sig = vec![0u8; MLDSA65_SIGNATURE_SIZE];
        let rc = unsafe {
            mt_sign_mldsa_ctx(
                sk_bytes.as_ptr(),
                msg_bytes.as_ptr(),
                msg_bytes.len(),
                ctx_bytes.as_ptr(),
                ctx_bytes.len(),
                sig.as_mut_ptr(),
            )
        };
        assert_eq!(
            rc, MT_OK,
            "tcId={} mt_sign_mldsa_ctx failed: {}",
            t.tc_id, rc
        );

        assert_eq!(
            sig, expected_sig,
            "tcId={} ctx_len={} ML-DSA-65 deterministic signature diverges from NIST FIPS 204 expected",
            t.tc_id,
            ctx_bytes.len()
        );
    }
    println!(
        "PASS: {}/{} ML-DSA-65 SigGen NIST KAT byte-exact (1 empty ctx + 14 non-empty)",
        kat.tests.len(),
        kat.tests.len()
    );
}

#[test]
fn siggen_empty_ctx_equivalence() {
    // Verify что mt_sign_mldsa(sk, msg) ≡ mt_sign_mldsa_ctx(sk, msg, &[], 0).
    // Empty context default — semantic equivalent для Montana usage pattern.
    let seed = [0x42u8; MLDSA65_SEED_SIZE];
    let mut pk = vec![0u8; MLDSA65_PUBKEY_SIZE];
    let mut sk = vec![0u8; MLDSA65_SECRETKEY_SIZE];
    unsafe {
        assert_eq!(
            mt_keypair_from_seed_mldsa(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()),
            MT_OK
        );
    }
    let msg = b"Montana sign equivalence test message";
    let mut sig_no_ctx = vec![0u8; MLDSA65_SIGNATURE_SIZE];
    let mut sig_empty_ctx = vec![0u8; MLDSA65_SIGNATURE_SIZE];
    unsafe {
        assert_eq!(
            mt_sign_mldsa(
                sk.as_ptr(),
                msg.as_ptr(),
                msg.len(),
                sig_no_ctx.as_mut_ptr()
            ),
            MT_OK
        );
        let empty_ctx: [u8; 0] = [];
        assert_eq!(
            mt_sign_mldsa_ctx(
                sk.as_ptr(),
                msg.as_ptr(),
                msg.len(),
                empty_ctx.as_ptr(),
                0,
                sig_empty_ctx.as_mut_ptr(),
            ),
            MT_OK
        );
    }
    assert_eq!(
        sig_no_ctx, sig_empty_ctx,
        "mt_sign_mldsa и mt_sign_mldsa_ctx с empty context должны давать одинаковую подпись"
    );
}

#[derive(Deserialize)]
struct MlKemDecapFile {
    source: String,
    tests: Vec<MlKemDecapTest>,
}

#[derive(Deserialize)]
struct MlKemDecapTest {
    #[serde(rename = "tcId")]
    tc_id: u32,
    dk: String,
    c: String,
    k: String,
}

#[test]
fn nist_acvp_ml_kem_768_decap_byte_exact() {
    let path = fixture_path("ml_kem_768_decap.json");
    let raw = fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("read fixture {}: {}", path.display(), e));
    let kat: MlKemDecapFile = serde_json::from_str(&raw).expect("parse ml_kem_768_decap.json");
    assert!(!kat.tests.is_empty(), "no tests in fixture");
    println!(
        "NIST ACVP ML-KEM-768 Decapsulation — {} tests from: {}",
        kat.tests.len(),
        kat.source
    );

    let mut passed = 0u32;
    for t in &kat.tests {
        let dk = hex_decode(&t.dk);
        let c = hex_decode(&t.c);
        let expected_k = hex_decode(&t.k);
        assert_eq!(dk.len(), MLKEM768_SECRETKEY_SIZE, "tcId={} dk len", t.tc_id);
        assert_eq!(c.len(), MLKEM768_CIPHERTEXT_SIZE, "tcId={} c len", t.tc_id);
        assert_eq!(expected_k.len(), 32, "tcId={} k len", t.tc_id);

        let mut ss = [0u8; 32];
        let rc = unsafe { mt_mlkem_decapsulate(dk.as_ptr(), c.as_ptr(), ss.as_mut_ptr()) };
        assert_eq!(rc, MT_OK, "tcId={} mt_mlkem_decapsulate failed", t.tc_id);
        assert_eq!(
            ss.as_slice(),
            expected_k.as_slice(),
            "tcId={} ML-KEM-768 decaps shared secret diverges from NIST FIPS 203 expected",
            t.tc_id
        );
        passed += 1;
    }
    println!(
        "PASS: {}/{} ML-KEM-768 Decapsulation NIST KAT byte-exact",
        passed,
        kat.tests.len()
    );
}
