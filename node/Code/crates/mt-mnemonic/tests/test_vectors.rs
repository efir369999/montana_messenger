// spec, раздел "Ключи → Мнемоника и seed" → M-1 binding test vectors для v29.9.1

use mt_codec::domain;
use mt_crypto::sha256_raw;
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

// === M-1 Test Vectors ===

#[test]
fn m1_vector_1_entropy_zero() {
    let entropy = [0u8; 32];
    let mnemonic = entropy_to_mnemonic(&entropy);
    println!("\n=== M-1 Vector 1: entropy = [0x00; 32] ===");
    println!("mnemonic: {mnemonic}");
    let master_seed = mnemonic_to_master_seed(&mnemonic).expect("valid");
    println!("master_seed: {}", hex(&master_seed));
    assert_eq!(
        hex(&master_seed),
        concat!(
            "38a1421ac3ce191fbdc46b1cca266a9d72d22320fb38bda6a3df90a1ead664a7",
            "8951703197be882ace38e0f557a492a8e9ff5e3c02290a8eecf5939468708edb",
        )
    );
}

#[test]
fn m1_vector_2_entropy_all_ff() {
    let entropy = [0xFFu8; 32];
    let mnemonic = entropy_to_mnemonic(&entropy);
    println!("\n=== M-1 Vector 2: entropy = [0xFF; 32] ===");
    println!("mnemonic: {mnemonic}");
    let master_seed = mnemonic_to_master_seed(&mnemonic).expect("valid");
    println!("master_seed: {}", hex(&master_seed));
    assert_eq!(
        hex(&master_seed),
        concat!(
            "a5925c51583447a0abe43b65dbc591f3780a91c7d44c6b333975a211096039f3",
            "d1d0ca9e125aa4e756f0a35b0006378ac69450e8254e32f16409a350f3ca9104",
        )
    );
}

#[test]
fn m1_vector_3_entropy_sha256_montana_test_vector_3() {
    let entropy_hash = sha256_raw(b"Montana test vector 3");
    let mut entropy = [0u8; 32];
    entropy.copy_from_slice(&entropy_hash);
    let mnemonic = entropy_to_mnemonic(&entropy);
    println!("\n=== M-1 Vector 3: entropy = SHA-256(\"Montana test vector 3\") ===");
    println!("entropy: {}", hex(&entropy));
    println!("mnemonic: {mnemonic}");
    let master_seed = mnemonic_to_master_seed(&mnemonic).expect("valid");
    println!("master_seed: {}", hex(&master_seed));
    assert_eq!(
        hex(&master_seed),
        concat!(
            "da13e259eb58c79a650c312efe79d2ef42861ad114206ec48cb4b1eb5dcf0c22",
            "75b074ef8b02fbc2123032090ff004d7cc546d2bbf34c4e10ec3c6fb092f9a47",
        )
    );
}

// === Per-role derivation Test Vectors (master_seed из M-1 Vector 1) ===

fn master_seed_vector_1() -> [u8; 64] {
    let entropy = [0u8; 32];
    let mnemonic = entropy_to_mnemonic(&entropy);
    mnemonic_to_master_seed(&mnemonic).expect("valid")
}

// Vectors regenerated для ML-DSA-65 seed length L=32 (was Falcon L=48).
// HKDF-Expand детерминирован: hex значения вычислены первым прогоном теста
// и зафиксированы как binding vectors.
#[test]
fn derivation_vector_1_mldsa_account() {
    let master = master_seed_vector_1();
    let mldsa_seed = mldsa_seed_for_role(&master, domain::ACCOUNT_KEY);
    println!("\n=== Derivation Vector 1: mldsa_seed(master_v1, \"mt-account-key\") ===");
    println!("mldsa_seed_32: {}", hex(&mldsa_seed));
    assert_eq!(
        hex(&mldsa_seed),
        "08ce5c19768c679fda24c0d3360e57ce03d00c94c175e59f50e9c77894c20818",
    );
}

#[test]
fn derivation_vector_2_mldsa_node() {
    let master = master_seed_vector_1();
    let mldsa_seed = mldsa_seed_for_role(&master, domain::NODE_KEY);
    println!("\n=== Derivation Vector 2: mldsa_seed(master_v1, \"mt-node-key\") ===");
    println!("mldsa_seed_32: {}", hex(&mldsa_seed));
    assert_eq!(
        hex(&mldsa_seed),
        "efe527d96de2cb82b3ee2e8ad24b4aca71014e37896b0c025a376335ad456acc",
    );
}

#[test]
fn derivation_vector_3_mlkem_app_encryption() {
    let master = master_seed_vector_1();
    let mlkem_seed = mlkem_seed_for_role(&master, domain::APP_ENCRYPTION_KEY);
    println!("\n=== Derivation Vector 3: mlkem_seed(master_v1, \"mt-app-encryption-key\") ===");
    println!("mlkem_seed_64: {}", hex(&mlkem_seed));
    assert_eq!(
        hex(&mlkem_seed),
        concat!(
            "3eb9bcd201a1d5e671c9d23a929589a26ceb53338cd0684b5d77314a14601b03",
            "9f3e2ae7e5e0be8acd47b4b928c3e73b5d875b9fc7089b22bc1d59e9dc31077e",
        )
    );
}
