// spec, раздел "Ключи → Мнемоника и seed". End-to-end recovery flow per [C-4]:
// от entropy через mnemonic + master_seed + per-role HKDF до **terminal observable
// outputs**: account_id (32B), node_id (32B), а также все 6 keypair частей
// (account pk/sk, node pk/sk, mlkem pk/sk).
//
// Идемпотентность: повторный прогон ВСЕЙ цепочки на той же entropy производит
// byte-identical terminal IDs и keypair bytes — это гарантия recovery flow
// (восстановление identity на новом устройстве из 24 слов).

use mt_codec::domain;
use mt_crypto::{
    keypair_from_seed, keypair_from_seed_mlkem, sha256_raw, MlkemPublicKey, MlkemSecretKey,
    PublicKey, SecretKey, SuiteId,
};
use mt_mnemonic::{
    entropy_to_mnemonic, mldsa_seed_for_role, mlkem_seed_for_role, mnemonic_to_master_seed,
};

// Terminal observable IDs (per spec):
//
//   account_id = SHA-256("mt-account" || 0x00 || suite_id_bytes (LE u16) || pk_acc)
//   node_id    = SHA-256("mt-node" || 0x00 || pk_node)

fn account_id(pk: &PublicKey) -> [u8; 32] {
    let mut buf = Vec::with_capacity(domain::ACCOUNT.len() + 3 + pk.as_bytes().len());
    buf.extend_from_slice(domain::ACCOUNT);
    buf.push(0u8); // канонический разделитель домена (конвенция hash() ядра)
    let suite_id = (SuiteId::Mldsa65 as u16).to_le_bytes();
    buf.extend_from_slice(&suite_id);
    buf.extend_from_slice(pk.as_bytes());
    sha256_raw(&buf)
}

fn node_id(pk: &PublicKey) -> [u8; 32] {
    let mut buf = Vec::with_capacity(domain::NODE.len() + 1 + pk.as_bytes().len());
    buf.extend_from_slice(domain::NODE);
    buf.push(0u8); // канонический разделитель домена
    buf.extend_from_slice(pk.as_bytes());
    sha256_raw(&buf)
}

struct Identity {
    pk_acc: PublicKey,
    sk_acc: SecretKey,
    pk_node: PublicKey,
    sk_node: SecretKey,
    pk_mlkem: MlkemPublicKey,
    sk_mlkem: MlkemSecretKey,
    account_id: [u8; 32],
    node_id: [u8; 32],
}

fn derive_identity(entropy: &[u8; 32]) -> Identity {
    // 1-2: entropy → mnemonic
    let mnemonic = entropy_to_mnemonic(entropy);
    // 3: mnemonic → master_seed (PBKDF2-HMAC-SHA-256, 2^20 iter)
    let master_seed = mnemonic_to_master_seed(&mnemonic).expect("valid mnemonic");

    // 4-5: account keypair
    let acc_seed = mldsa_seed_for_role(&master_seed, domain::ACCOUNT_KEY);
    let (pk_acc, sk_acc) = keypair_from_seed(&acc_seed).expect("account keygen");
    // 6: account_id terminal
    let aid = account_id(&pk_acc);

    // 7-8: node keypair
    let node_seed = mldsa_seed_for_role(&master_seed, domain::NODE_KEY);
    let (pk_node, sk_node) = keypair_from_seed(&node_seed).expect("node keygen");
    // 9: node_id terminal
    let nid = node_id(&pk_node);

    // 10-11: app encryption keypair (ML-KEM-768)
    let mlkem_seed = mlkem_seed_for_role(&master_seed, domain::APP_ENCRYPTION_KEY);
    let (pk_mlkem, sk_mlkem) = keypair_from_seed_mlkem(&mlkem_seed).expect("mlkem keygen");

    Identity {
        pk_acc,
        sk_acc,
        pk_node,
        sk_node,
        pk_mlkem,
        sk_mlkem,
        account_id: aid,
        node_id: nid,
    }
}

#[test]
fn e2e_recovery_terminal_observable_byte_exact() {
    // Step 1: entropy = [0xAB; 32] — фиксированный test input
    let entropy = [0xABu8; 32];

    // Steps 2-11: первое derivation
    let id1 = derive_identity(&entropy);

    // Step 12: ПОВТОРИТЬ шаги 2-11 → второе derivation
    let id2 = derive_identity(&entropy);

    // Steps 13-14: terminal IDs byte-exact
    assert_eq!(
        id1.account_id, id2.account_id,
        "account_id terminal mismatch"
    );
    assert_eq!(id1.node_id, id2.node_id, "node_id terminal mismatch");

    // Step 15: все 6 key parts byte-exact
    assert_eq!(
        id1.pk_acc.as_bytes(),
        id2.pk_acc.as_bytes(),
        "account pk mismatch"
    );
    assert_eq!(
        id1.sk_acc.as_bytes(),
        id2.sk_acc.as_bytes(),
        "account sk mismatch"
    );
    assert_eq!(
        id1.pk_node.as_bytes(),
        id2.pk_node.as_bytes(),
        "node pk mismatch"
    );
    assert_eq!(
        id1.sk_node.as_bytes(),
        id2.sk_node.as_bytes(),
        "node sk mismatch"
    );
    assert_eq!(
        id1.pk_mlkem.as_bytes(),
        id2.pk_mlkem.as_bytes(),
        "mlkem pk mismatch"
    );
    assert_eq!(
        id1.sk_mlkem.as_bytes(),
        id2.sk_mlkem.as_bytes(),
        "mlkem sk mismatch"
    );
}

#[test]
fn e2e_recovery_distinct_entropies_produce_distinct_terminals() {
    let id1 = derive_identity(&[0x00u8; 32]);
    let id2 = derive_identity(&[0xFFu8; 32]);
    assert_ne!(id1.account_id, id2.account_id);
    assert_ne!(id1.node_id, id2.node_id);
    assert_ne!(id1.pk_acc.as_bytes(), id2.pk_acc.as_bytes());
    assert_ne!(id1.pk_node.as_bytes(), id2.pk_node.as_bytes());
    assert_ne!(id1.pk_mlkem.as_bytes(), id2.pk_mlkem.as_bytes());
}

#[test]
fn e2e_recovery_account_node_keys_differ_from_same_master() {
    // Domain separation per HKDF info: ACCOUNT_KEY vs NODE_KEY → разные ML-DSA seeds
    // → разные pk → разные account_id / node_id даже на одной мнемонике.
    let id = derive_identity(&[0x42u8; 32]);
    assert_ne!(
        id.pk_acc.as_bytes(),
        id.pk_node.as_bytes(),
        "account и node pk должны различаться (HKDF domain separation)"
    );
    assert_ne!(
        id.account_id, id.node_id,
        "account_id и node_id должны различаться"
    );
}
