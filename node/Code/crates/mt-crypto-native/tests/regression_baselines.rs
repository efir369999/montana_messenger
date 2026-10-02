use mt_crypto_native::{
    mt_keypair_from_seed_mldsa, mt_keypair_from_seed_mlkem, mt_self_test, mt_sign_mldsa,
    mt_verify_mldsa, MLDSA65_PUBKEY_SIZE, MLDSA65_SECRETKEY_SIZE, MLDSA65_SEED_SIZE,
    MLDSA65_SIGNATURE_SIZE, MLKEM768_PUBKEY_SIZE, MLKEM768_SECRETKEY_SIZE, MLKEM768_SEED_SIZE,
    MT_OK,
};

fn sha256_hex(data: &[u8]) -> String {
    use std::io::Write;
    use std::process::{Command, Stdio};
    let mut child = Command::new("shasum")
        .args(["-a", "256"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("shasum spawn");
    child
        .stdin
        .as_mut()
        .expect("stdin")
        .write_all(data)
        .expect("write");
    let out = child.wait_with_output().expect("wait");
    let s = String::from_utf8(out.stdout).expect("utf8");
    s.split_whitespace().next().expect("hash").to_string()
}

#[test]
fn mldsa_keypair_from_zero_seed_deterministic() {
    let seed = [0u8; MLDSA65_SEED_SIZE];
    let mut pk1 = vec![0u8; MLDSA65_PUBKEY_SIZE];
    let mut sk1 = vec![0u8; MLDSA65_SECRETKEY_SIZE];
    let mut pk2 = vec![0u8; MLDSA65_PUBKEY_SIZE];
    let mut sk2 = vec![0u8; MLDSA65_SECRETKEY_SIZE];

    unsafe {
        assert_eq!(
            mt_keypair_from_seed_mldsa(seed.as_ptr(), pk1.as_mut_ptr(), sk1.as_mut_ptr()),
            MT_OK
        );
        assert_eq!(
            mt_keypair_from_seed_mldsa(seed.as_ptr(), pk2.as_mut_ptr(), sk2.as_mut_ptr()),
            MT_OK
        );
    }

    assert_eq!(pk1, pk2, "ML-DSA pubkey deterministic из одного seed");
    assert_eq!(sk1, sk2, "ML-DSA secretkey deterministic из одного seed");

    let pk_hash = sha256_hex(&pk1);
    let sk_hash = sha256_hex(&sk1);
    println!("ML-DSA-65 zero-seed pk SHA-256: {pk_hash}");
    println!("ML-DSA-65 zero-seed sk SHA-256: {sk_hash}");

    assert_eq!(
        pk_hash, "085ba380ff386dd52e42349c6eb88489d6058ea541a4e3fb0dce9a3fd1f7a911",
        "ML-DSA-65 zero-seed pubkey baseline (M1-F Phase 1.3 первый прогон)"
    );
    assert_eq!(
        sk_hash, "cfcb5e7edf4348f712b7002b0553d28929856936c98e4adf172e51d5c9934262",
        "ML-DSA-65 zero-seed secretkey baseline (M1-F Phase 1.3 первый прогон)"
    );
}

#[test]
fn mldsa_keypair_from_montana_seed_deterministic() {
    let mut seed = [0u8; MLDSA65_SEED_SIZE];
    let bytes = b"Montana test vector ML-DSA-65 \x00\x00";
    seed.copy_from_slice(&bytes[..MLDSA65_SEED_SIZE]);

    let mut pk = vec![0u8; MLDSA65_PUBKEY_SIZE];
    let mut sk = vec![0u8; MLDSA65_SECRETKEY_SIZE];

    unsafe {
        assert_eq!(
            mt_keypair_from_seed_mldsa(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()),
            MT_OK
        );
    }

    let pk_hash = sha256_hex(&pk);
    let sk_hash = sha256_hex(&sk);
    println!("ML-DSA-65 montana-seed pk SHA-256: {pk_hash}");
    println!("ML-DSA-65 montana-seed sk SHA-256: {sk_hash}");

    assert_eq!(
        pk_hash, "aa6bc11dd32e4aa8ccf3d43400c4ef29ab86582bdc83738aa5f302a63e38bfba",
        "ML-DSA-65 montana-seed pubkey baseline"
    );
    assert_eq!(
        sk_hash, "c6acdd04cdbe004977db8297cf3c7dfb6d5733ebb5bb6d64fc0259c933902fda",
        "ML-DSA-65 montana-seed secretkey baseline"
    );
}

#[test]
fn mlkem_keypair_from_zero_seed_deterministic() {
    let seed = [0u8; MLKEM768_SEED_SIZE];
    let mut pk1 = vec![0u8; MLKEM768_PUBKEY_SIZE];
    let mut sk1 = vec![0u8; MLKEM768_SECRETKEY_SIZE];
    let mut pk2 = vec![0u8; MLKEM768_PUBKEY_SIZE];
    let mut sk2 = vec![0u8; MLKEM768_SECRETKEY_SIZE];

    unsafe {
        assert_eq!(
            mt_keypair_from_seed_mlkem(seed.as_ptr(), pk1.as_mut_ptr(), sk1.as_mut_ptr()),
            MT_OK
        );
        assert_eq!(
            mt_keypair_from_seed_mlkem(seed.as_ptr(), pk2.as_mut_ptr(), sk2.as_mut_ptr()),
            MT_OK
        );
    }

    assert_eq!(pk1, pk2, "ML-KEM pubkey deterministic из одного seed");
    assert_eq!(sk1, sk2, "ML-KEM secretkey deterministic из одного seed");

    let pk_hash = sha256_hex(&pk1);
    let sk_hash = sha256_hex(&sk1);
    println!("ML-KEM-768 zero-seed pk SHA-256: {pk_hash}");
    println!("ML-KEM-768 zero-seed sk SHA-256: {sk_hash}");

    assert_eq!(
        pk_hash, "f95c185fe5b2335d2fc938dd889c6425944acd74376b6952bf1130f720f6ba99",
        "ML-KEM-768 zero-seed pubkey baseline"
    );
    assert_eq!(
        sk_hash, "a5e078867af0c0a9702149b3af1adf208dccf878bc9f9e32d4fb028473addd09",
        "ML-KEM-768 zero-seed secretkey baseline"
    );
}

#[test]
fn mlkem_keypair_from_ones_seed_deterministic() {
    let seed = [0xFFu8; MLKEM768_SEED_SIZE];
    let mut pk = vec![0u8; MLKEM768_PUBKEY_SIZE];
    let mut sk = vec![0u8; MLKEM768_SECRETKEY_SIZE];

    unsafe {
        assert_eq!(
            mt_keypair_from_seed_mlkem(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()),
            MT_OK
        );
    }

    let pk_hash = sha256_hex(&pk);
    let sk_hash = sha256_hex(&sk);
    println!("ML-KEM-768 ones-seed pk SHA-256: {pk_hash}");
    println!("ML-KEM-768 ones-seed sk SHA-256: {sk_hash}");

    assert_eq!(
        pk_hash, "b212c1e61145cc7f4fb3ff1e6adf823f66a69e0fca3cd7d571ab259a96348509",
        "ML-KEM-768 ones-seed pubkey baseline"
    );
    assert_eq!(
        sk_hash, "a958f21bfaf882fdeada66f18774b8dc10ff7e3f7fcacc8e295b2dc138d23998",
        "ML-KEM-768 ones-seed secretkey baseline"
    );
}

#[test]
fn mldsa_sign_verify_roundtrip() {
    let seed = [0u8; MLDSA65_SEED_SIZE];
    let mut pk = vec![0u8; MLDSA65_PUBKEY_SIZE];
    let mut sk = vec![0u8; MLDSA65_SECRETKEY_SIZE];

    unsafe {
        assert_eq!(
            mt_keypair_from_seed_mldsa(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()),
            MT_OK
        );
    }

    let msg = b"Montana protocol test message for ML-DSA-65 sign/verify roundtrip";
    let mut sig1 = vec![0u8; MLDSA65_SIGNATURE_SIZE];
    let mut sig2 = vec![0u8; MLDSA65_SIGNATURE_SIZE];

    unsafe {
        assert_eq!(
            mt_sign_mldsa(sk.as_ptr(), msg.as_ptr(), msg.len(), sig1.as_mut_ptr()),
            MT_OK
        );
        assert_eq!(
            mt_sign_mldsa(sk.as_ptr(), msg.as_ptr(), msg.len(), sig2.as_mut_ptr()),
            MT_OK
        );
    }

    assert_eq!(sig1, sig2, "ML-DSA подпись deterministic per FIPS 204");

    unsafe {
        assert_eq!(
            mt_verify_mldsa(pk.as_ptr(), msg.as_ptr(), msg.len(), sig1.as_ptr()),
            MT_OK,
            "verify должен принять корректную подпись"
        );
    }

    let bad_msg = b"Montana protocol DIFFERENT message for ML-DSA-65 sign/verify roundtrip";
    unsafe {
        let rc = mt_verify_mldsa(pk.as_ptr(), bad_msg.as_ptr(), bad_msg.len(), sig1.as_ptr());
        assert_ne!(
            rc, MT_OK,
            "verify должен отклонить подпись на изменённое сообщение"
        );
    }

    let mut tampered_sig = sig1.clone();
    tampered_sig[0] ^= 0x01;
    unsafe {
        let rc = mt_verify_mldsa(pk.as_ptr(), msg.as_ptr(), msg.len(), tampered_sig.as_ptr());
        assert_ne!(rc, MT_OK, "verify должен отклонить tampered подпись");
    }

    let sig_hash = sha256_hex(&sig1);
    println!("ML-DSA-65 zero-seed roundtrip sig SHA-256: {sig_hash}");
    assert_eq!(
        sig_hash, "56a3c55492021ce47a4dbab2ee7965b9d52979650184973177f2c7d9f66aad03",
        "ML-DSA-65 deterministic signature baseline (zero-seed key, fixed test message)"
    );
}

#[test]
fn self_test_passes() {
    unsafe {
        assert_eq!(mt_self_test(), MT_OK);
    }
}
