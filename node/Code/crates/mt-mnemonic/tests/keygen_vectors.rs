// spec, раздел "Ключи → Test vectors (binding) → KeyGen output binding vectors".
//
// 5 KAT vectors для terminal observable output identity recovery flow per [C-4].
//
// Binding values: SHA-256(pk) и SHA-256(sk) для каждого KAT — byte-exact
// идентификация полного pk / sk. Cross-implementation сверка через эти
// 32-байтовые fingerprints гарантирует byte-equivalence полных pk / sk
// (collision-resistance SHA-256 → одинаковый hash ⇔ одинаковый input).
//
// Полные pk / sk hex доступны через `cargo test ... -- --nocapture` для
// независимой regeneration. См. также `mt-crypto::self_test()` который
// проверяет KAT 1 inline.

use mt_codec::domain;
use mt_crypto::{
    keypair_from_seed, keypair_from_seed_mlkem, sha256_raw, MLKEM_PUBLIC_KEY_SIZE,
    MLKEM_SECRET_KEY_SIZE, PUBLIC_KEY_SIZE, SECRET_KEY_SIZE,
};
use mt_mnemonic::{
    entropy_to_mnemonic, mldsa_seed_for_role, mlkem_seed_for_role, mnemonic_to_master_seed,
};

fn hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

fn master_seed_v1() -> [u8; 64] {
    let entropy = [0u8; 32];
    let mnemonic = entropy_to_mnemonic(&entropy);
    mnemonic_to_master_seed(&mnemonic).expect("valid")
}

// === Binding KAT fingerprints (SHA-256 of pk and sk) ===
// Любая реализация ML-DSA-65 / ML-KEM-768 обязана воспроизводить идентичные
// pk и sk байты для тех же seed inputs → идентичные SHA-256 fingerprints.

pub const KAT_1_PK_SHA256: &str =
    "085ba380ff386dd52e42349c6eb88489d6058ea541a4e3fb0dce9a3fd1f7a911";
pub const KAT_1_SK_SHA256: &str =
    "cfcb5e7edf4348f712b7002b0553d28929856936c98e4adf172e51d5c9934262";

pub const KAT_2_PK_SHA256: &str =
    "accc50ec0bce614855e62e04741f54367add7a6ec074db7369f7484e6067e224";
pub const KAT_2_SK_SHA256: &str =
    "11681dc1c20ee8ab3198e19858b1498c25f49c301d9c2f2256b8db4c1ef0dcae";

pub const KAT_3_PK_SHA256: &str =
    "a1e69b6a4e0c1740c3800852553b1609ab46e8dd48f6b94bfbd81503135fff00";
pub const KAT_3_SK_SHA256: &str =
    "37e717acb23f20afd1d4e2df6f43f7a8334ae858f4ab7efeefba7b9630bdbaf7";

pub const KAT_4_PK_SHA256: &str =
    "8edc3910369546b8c1df465cf151057d98d76a862fc00f8d0718189cffcdd70d";
pub const KAT_4_SK_SHA256: &str =
    "478bf531c2b081adca30ae7ac31fbbcc6c0eeaa92fcd38d3f9960f4ad13ecfd4";

pub const KAT_5_PK_SHA256: &str =
    "b827d37b2b225907c835f25a8652c215af69f8f52bd6a7ef0ae31955d63fd1c4";
pub const KAT_5_SK_SHA256: &str =
    "685c8c5299dde1176c4145a8af6dd08f2773f5551a7df29c3b1f7b6faba439b3";

#[test]
fn kat_1_mldsa_seed_zero() {
    let seed = [0x00u8; 32];
    let (pk, sk) = keypair_from_seed(&seed).expect("keygen");
    assert_eq!(pk.as_bytes().len(), PUBLIC_KEY_SIZE);
    assert_eq!(sk.as_bytes().len(), SECRET_KEY_SIZE);
    let pk_h = hex(&sha256_raw(pk.as_bytes()));
    let sk_h = hex(&sha256_raw(sk.as_bytes()));
    println!("\n=== KAT 1: ML-DSA-65.KeyGen([0x00; 32]) ===");
    println!("pk_sha256 = {pk_h}");
    println!("sk_sha256 = {sk_h}");
    assert_eq!(pk_h, KAT_1_PK_SHA256);
    assert_eq!(sk_h, KAT_1_SK_SHA256);
}

#[test]
fn kat_2_mldsa_seed_ff() {
    let seed = [0xFFu8; 32];
    let (pk, sk) = keypair_from_seed(&seed).expect("keygen");
    assert_eq!(pk.as_bytes().len(), PUBLIC_KEY_SIZE);
    assert_eq!(sk.as_bytes().len(), SECRET_KEY_SIZE);
    let pk_h = hex(&sha256_raw(pk.as_bytes()));
    let sk_h = hex(&sha256_raw(sk.as_bytes()));
    println!("\n=== KAT 2: ML-DSA-65.KeyGen([0xFF; 32]) ===");
    println!("pk_sha256 = {pk_h}");
    println!("sk_sha256 = {sk_h}");
    assert_eq!(pk_h, KAT_2_PK_SHA256);
    assert_eq!(sk_h, KAT_2_SK_SHA256);
}

#[test]
fn kat_3_mldsa_account_from_master_v1() {
    let master = master_seed_v1();
    let seed = mldsa_seed_for_role(&master, domain::ACCOUNT_KEY);
    assert_eq!(
        hex(&seed),
        "08ce5c19768c679fda24c0d3360e57ce03d00c94c175e59f50e9c77894c20818"
    );
    let (pk, sk) = keypair_from_seed(&seed).expect("keygen");
    assert_eq!(pk.as_bytes().len(), PUBLIC_KEY_SIZE);
    assert_eq!(sk.as_bytes().len(), SECRET_KEY_SIZE);
    let pk_h = hex(&sha256_raw(pk.as_bytes()));
    let sk_h = hex(&sha256_raw(sk.as_bytes()));
    println!("\n=== KAT 3: ML-DSA-65.KeyGen(mldsa_seed(master_v1, ACCOUNT_KEY)) ===");
    println!("pk_sha256 = {pk_h}");
    println!("sk_sha256 = {sk_h}");
    assert_eq!(pk_h, KAT_3_PK_SHA256);
    assert_eq!(sk_h, KAT_3_SK_SHA256);
}

#[test]
fn kat_4_mldsa_node_from_master_v1() {
    let master = master_seed_v1();
    let seed = mldsa_seed_for_role(&master, domain::NODE_KEY);
    assert_eq!(
        hex(&seed),
        "efe527d96de2cb82b3ee2e8ad24b4aca71014e37896b0c025a376335ad456acc"
    );
    let (pk, sk) = keypair_from_seed(&seed).expect("keygen");
    assert_eq!(pk.as_bytes().len(), PUBLIC_KEY_SIZE);
    assert_eq!(sk.as_bytes().len(), SECRET_KEY_SIZE);
    let pk_h = hex(&sha256_raw(pk.as_bytes()));
    let sk_h = hex(&sha256_raw(sk.as_bytes()));
    println!("\n=== KAT 4: ML-DSA-65.KeyGen(mldsa_seed(master_v1, NODE_KEY)) ===");
    println!("pk_sha256 = {pk_h}");
    println!("sk_sha256 = {sk_h}");
    assert_eq!(pk_h, KAT_4_PK_SHA256);
    assert_eq!(sk_h, KAT_4_SK_SHA256);
}

#[test]
fn kat_5_mlkem_app_from_master_v1() {
    let master = master_seed_v1();
    let seed = mlkem_seed_for_role(&master, domain::APP_ENCRYPTION_KEY);
    let (pk, sk) = keypair_from_seed_mlkem(&seed).expect("keygen mlkem");
    assert_eq!(pk.as_bytes().len(), MLKEM_PUBLIC_KEY_SIZE);
    assert_eq!(sk.as_bytes().len(), MLKEM_SECRET_KEY_SIZE);
    let pk_h = hex(&sha256_raw(pk.as_bytes()));
    let sk_h = hex(&sha256_raw(sk.as_bytes()));
    println!("\n=== KAT 5: ML-KEM-768.KeyGen(mlkem_seed(master_v1, APP_ENCRYPTION_KEY)) ===");
    println!("pk_sha256 = {pk_h}");
    println!("sk_sha256 = {sk_h}");
    assert_eq!(pk_h, KAT_5_PK_SHA256);
    assert_eq!(sk_h, KAT_5_SK_SHA256);
}

#[test]
fn determinism_kat_3() {
    let master = master_seed_v1();
    let seed = mldsa_seed_for_role(&master, domain::ACCOUNT_KEY);
    let (pk1, sk1) = keypair_from_seed(&seed).expect("keygen 1");
    let (pk2, sk2) = keypair_from_seed(&seed).expect("keygen 2");
    assert_eq!(pk1.as_bytes(), pk2.as_bytes());
    assert_eq!(sk1.as_bytes(), sk2.as_bytes());
}

#[test]
fn determinism_kat_5() {
    let master = master_seed_v1();
    let seed = mlkem_seed_for_role(&master, domain::APP_ENCRYPTION_KEY);
    let (pk1, sk1) = keypair_from_seed_mlkem(&seed).expect("keygen mlkem 1");
    let (pk2, sk2) = keypair_from_seed_mlkem(&seed).expect("keygen mlkem 2");
    assert_eq!(pk1.as_bytes(), pk2.as_bytes());
    assert_eq!(sk1.as_bytes(), sk2.as_bytes());
}
