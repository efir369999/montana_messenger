//! End-to-end test of Stages 5+6 on the byte-level crypto API (cfg fork).

use mt_messenger_e2e::crypto::{dsa_pub_from_seed, kem_keypair_from_seed, MLDSA_PUB, MLKEM_PUB};
use mt_messenger_e2e::handshake::{
    account_id, build_handshake, process_handshake, RecipientBundle, RecipientKeys,
};
use mt_messenger_e2e::session::SessionState;

fn setup() -> (SessionState, SessionState) {
    let (app_pub, app_sk) = kem_keypair_from_seed(&[0x11; 64]).unwrap();
    let (spk_pub, spk_sk) = kem_keypair_from_seed(&[0x22; 64]).unwrap();
    let (opk_pub, opk_sk) = kem_keypair_from_seed(&[0x33; 64]).unwrap();
    let bob_pub: [u8; MLDSA_PUB] = dsa_pub_from_seed(&[0x44; 32]).unwrap();
    let bob_id = account_id(&bob_pub);
    let alice_pub: [u8; MLDSA_PUB] = dsa_pub_from_seed(&[0x55; 32]).unwrap();

    let bundle = RecipientBundle {
        account_key_pub: &bob_pub,
        app_kem_pub: &app_pub,
        signed_prekey_pub: &spk_pub,
        spk_id: 7,
        one_time: Some((99, &opk_pub)),
    };
    let hs = build_handshake(&alice_pub, &[0x55; 32], &bundle, &[0x66; 64], 1000).unwrap();
    let keys = RecipientKeys {
        account_id: &bob_id,
        app_kem_pub: &app_pub,
        app_kem_sk: &app_sk,
        signed_prekey_pub: &spk_pub,
        signed_prekey_sk: &spk_sk,
        one_time: Some((&opk_pub, &opk_sk)),
    };
    let proc = process_handshake(&hs.bytes, &keys, 1001, 604800).unwrap();
    assert_eq!(hs.session.root_key, proc.session.root_key);

    let _ = (opk_pub, opk_sk, MLKEM_PUB);
    let (_spk_pub2, spk_sk2) = kem_keypair_from_seed(&[0x22; 64]).unwrap();
    let alice = SessionState::init_initiator(
        hs.transcript_hash,
        hs.session.root_key,
        hs.session.sending_chain_key,
        hs.eph_kem_pub_a,
        hs.eph_kem_sk_a,
        hs.signed_prekey_pub_b,
    );
    let bob = SessionState::init_responder(
        proc.transcript_hash,
        proc.session.root_key,
        proc.session.sending_chain_key,
        proc.eph_kem_pub_a,
        spk_pub,
        spk_sk2,
    );
    (alice, bob)
}

#[test]
fn full_flow_bidirectional() {
    let (mut alice, mut bob) = setup();
    let m1 = alice.encrypt(b"privet Bob", &[0xA1; 64]).unwrap();
    assert_eq!(bob.decrypt(&m1).unwrap(), b"privet Bob");
    let r1 = bob.encrypt(b"privet Alice", &[0xB1; 64]).unwrap();
    assert_eq!(alice.decrypt(&r1).unwrap(), b"privet Alice");
    let m2 = alice.encrypt(b"kak dela", &[0xA2; 64]).unwrap();
    assert_eq!(bob.decrypt(&m2).unwrap(), b"kak dela");
    let r2 = bob.encrypt(b"otlichno", &[0xB2; 64]).unwrap();
    assert_eq!(alice.decrypt(&r2).unwrap(), b"otlichno");
}

#[test]
fn out_of_order_delivery() {
    let (mut alice, mut bob) = setup();
    let a = alice.encrypt(b"msg-1", &[0xA1; 64]).unwrap();
    let b = alice.encrypt(b"msg-2", &[0xA2; 64]).unwrap();
    let c = alice.encrypt(b"msg-3", &[0xA3; 64]).unwrap();
    assert_eq!(bob.decrypt(&a).unwrap(), b"msg-1");
    assert_eq!(bob.decrypt(&c).unwrap(), b"msg-3");
    assert_eq!(bob.decrypt(&b).unwrap(), b"msg-2");
}

#[test]
fn forged_message_does_not_advance() {
    let (mut alice, mut bob) = setup();
    let m1 = alice.encrypt(b"real", &[0xA1; 64]).unwrap();
    let mut forged = m1.clone();
    let n = forged.len();
    forged[n - 1] ^= 1;
    assert!(bob.decrypt(&forged).is_err());
    assert_eq!(bob.decrypt(&m1).unwrap(), b"real");
}

#[test]
fn session_survives_serialization() {
    let (mut alice, mut bob) = setup();
    let m1 = alice.encrypt(b"first", &[0xA1; 64]).unwrap();
    assert_eq!(bob.decrypt(&m1).unwrap(), b"first");
    let blob = bob.to_bytes();
    let mut bob2 = SessionState::from_bytes(&blob).unwrap();
    let r1 = bob2.encrypt(b"after-reload", &[0xB1; 64]).unwrap();
    assert_eq!(alice.decrypt(&r1).unwrap(), b"after-reload");
    let m2 = alice.encrypt(b"second", &[0xA2; 64]).unwrap();
    assert_eq!(bob2.decrypt(&m2).unwrap(), b"second");
}

#[test]
fn replay_below_cursor_keeps_session() {
    use mt_messenger_e2e::session::RatchetError;
    let (mut alice, mut bob) = setup();
    let m1 = alice.encrypt(b"one", &[0xA1; 64]).unwrap();
    let m2 = alice.encrypt(b"two", &[0xA2; 64]).unwrap();
    assert_eq!(bob.decrypt(&m1).unwrap(), b"one");
    assert_eq!(bob.decrypt(&m2).unwrap(), b"two");
    assert_eq!(bob.decrypt(&m1).unwrap_err(), RatchetError::Replay);
    assert_eq!(bob.decrypt(&m2).unwrap_err(), RatchetError::Replay);
    let m3 = alice.encrypt(b"three", &[0xA3; 64]).unwrap();
    assert_eq!(bob.decrypt(&m3).unwrap(), b"three");
    let r = bob.encrypt(b"reply", &[0xB1; 64]).unwrap();
    assert_eq!(alice.decrypt(&r).unwrap(), b"reply");
}
