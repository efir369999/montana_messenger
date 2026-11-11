use mt_crypto::{
    keypair_from_seed_mlkem, mlkem_decapsulate, mlkem_encapsulate, MLKEM_CIPHERTEXT_SIZE,
    MLKEM_SHARED_SECRET_SIZE,
};

#[test]
fn mlkem_encap_decap_roundtrip() {
    let seed = [0x42u8; mt_crypto::MLKEM_SEED_SIZE];
    let (pk, sk) = keypair_from_seed_mlkem(&seed).unwrap();

    let (ct, ss_sender) = mlkem_encapsulate(&pk).unwrap();
    assert_eq!(ct.as_bytes().len(), MLKEM_CIPHERTEXT_SIZE);

    let ss_receiver = mlkem_decapsulate(&sk, &ct).unwrap();
    assert_eq!(ss_receiver.as_bytes().len(), MLKEM_SHARED_SECRET_SIZE);
    assert_eq!(ss_sender.as_bytes(), ss_receiver.as_bytes());
}

#[test]
fn mlkem_encap_produces_distinct_ciphertexts() {
    let seed = [0x33u8; mt_crypto::MLKEM_SEED_SIZE];
    let (pk, sk) = keypair_from_seed_mlkem(&seed).unwrap();
    let (ct1, _ss1) = mlkem_encapsulate(&pk).unwrap();
    let (ct2, _ss2) = mlkem_encapsulate(&pk).unwrap();
    assert_ne!(
        ct1.as_bytes(),
        ct2.as_bytes(),
        "encap must use fresh OS randomness per FIPS 203"
    );
    let ss1 = mlkem_decapsulate(&sk, &ct1).unwrap();
    let ss2 = mlkem_decapsulate(&sk, &ct2).unwrap();
    assert_ne!(
        ss1.as_bytes(),
        ss2.as_bytes(),
        "distinct ciphertexts → distinct shared secrets"
    );
}
