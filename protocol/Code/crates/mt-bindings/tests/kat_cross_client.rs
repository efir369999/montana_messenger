//! KAT (Known-Answer Test) -- byte-exact reference. iOS/Android/Web implementations
//! must produce identical values for the same mnemonic.

use mt_codec::domain;
use mt_crypto::{keypair_from_seed, sign as mldsa_sign, verify as mldsa_verify};
use mt_mnemonic::{entropy_to_mnemonic, mldsa_seed_for_role, mnemonic_to_master_seed};
use mt_state::derive_account_id;

const MT_SUITE_MLDSA65: u16 = 0x0001;
const ENTROPY_ZERO: [u8; 32] = [0u8; 32];

#[test]
fn kat_entropy_zero_to_account_id() {
    let mnemonic = entropy_to_mnemonic(&ENTROPY_ZERO);
    assert_eq!(mnemonic.split_whitespace().count(), 24);

    let master = mnemonic_to_master_seed(&mnemonic).expect("master seed");
    let acc_seed = mldsa_seed_for_role(&master, domain::ACCOUNT_KEY);
    let (pk, _sk) = keypair_from_seed(&acc_seed).expect("keypair");
    let account_id = derive_account_id(MT_SUITE_MLDSA65, pk.as_bytes());

    eprintln!("=== KAT vector #1 (entropy = 32×0x00) ===");
    eprintln!("mnemonic    : {mnemonic}");
    eprintln!("master[..8] : {}", hex::encode(&master[..8]));
    eprintln!("acc_seed    : {}", hex::encode(acc_seed));
    eprintln!("pubkey[..16]: {}", hex::encode(&pk.as_bytes()[..16]));
    eprintln!("account_id  : {}", hex::encode(account_id));

    // Binding vector (spec Stage 1): entropy=0 -> fixed account_id + address.
    assert_eq!(
        hex::encode(account_id),
        "9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21"
    );
    assert_eq!(
        mt_bindings::account_id_to_address(&account_id),
        "mt2D4zg5S4qjjNLmuqLZsuS9rwMUoa47SgmQ7RQvkW7hfVmaRgfb"
    );
}

#[test]
fn determinism() {
    let mnemonic = entropy_to_mnemonic(&ENTROPY_ZERO);
    let master1 = mnemonic_to_master_seed(&mnemonic).unwrap();
    let master2 = mnemonic_to_master_seed(&mnemonic).unwrap();
    assert_eq!(master1, master2);
    let s1 = mldsa_seed_for_role(&master1, domain::ACCOUNT_KEY);
    let s2 = mldsa_seed_for_role(&master2, domain::ACCOUNT_KEY);
    assert_eq!(s1, s2);
    let (pk1, _) = keypair_from_seed(&s1).unwrap();
    let (pk2, _) = keypair_from_seed(&s2).unwrap();
    assert_eq!(pk1.as_bytes(), pk2.as_bytes());
    let id1 = derive_account_id(MT_SUITE_MLDSA65, pk1.as_bytes());
    let id2 = derive_account_id(MT_SUITE_MLDSA65, pk2.as_bytes());
    assert_eq!(id1, id2);
}

#[test]
fn sign_verify_roundtrip() {
    let mnemonic = entropy_to_mnemonic(&ENTROPY_ZERO);
    let master = mnemonic_to_master_seed(&mnemonic).unwrap();
    let s = mldsa_seed_for_role(&master, domain::ACCOUNT_KEY);
    let (pk, sk) = keypair_from_seed(&s).unwrap();
    let msg = b"montana mainnet test";
    let sig = mldsa_sign(&sk, msg).unwrap();
    assert!(mldsa_verify(&pk, msg, &sig));
    assert!(!mldsa_verify(&pk, b"tampered", &sig));
}
