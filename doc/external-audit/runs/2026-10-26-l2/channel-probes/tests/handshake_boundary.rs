// Published F-13 boundary check; selected parser coverage, not exhaustive fuzzing.
use mt_messenger_e2e::crypto::{dsa_pub_from_seed, kem_keypair_from_seed, MLDSA_PUB, MLKEM_PUB};
use mt_messenger_e2e::handshake::{
    account_id, build_handshake, process_handshake, E2eError, RecipientBundle, RecipientKeys,
};

#[test]
fn valid_handshakes_reject_every_truncated_prefix_and_appended_byte() {
    let (app_pub, app_sk) = kem_keypair_from_seed(&[0x11; 64]).unwrap();
    let (spk_pub, spk_sk) = kem_keypair_from_seed(&[0x22; 64]).unwrap();
    let (opk_pub, opk_sk) = kem_keypair_from_seed(&[0x33; 64]).unwrap();
    let bob_pub = dsa_pub_from_seed(&[0x44; 32]).unwrap();
    let alice_pub = dsa_pub_from_seed(&[0x55; 32]).unwrap();
    let bob_id = account_id(&bob_pub);
    let mut checked = 0;
    for with_opk in [false, true] {
        let bundle = RecipientBundle {
            account_key_pub: &bob_pub,
            app_kem_pub: &app_pub,
            signed_prekey_pub: &spk_pub,
            spk_id: 7,
            one_time: with_opk.then_some((99, &opk_pub)),
        };
        let keys = RecipientKeys {
            account_id: &bob_id,
            app_kem_pub: &app_pub,
            app_kem_sk: &app_sk,
            signed_prekey_pub: &spk_pub,
            signed_prekey_sk: &spk_sk,
            one_time: with_opk.then_some((&opk_pub, opk_sk.as_slice())),
        };
        let hs = build_handshake(&alice_pub, &[0x55; 32], &bundle, &[0x66; 64], 1000)
            .expect("valid fixture");
        let received = process_handshake(&hs.bytes, &keys, 1000, 0).unwrap();
        assert_eq!(received.session.root_key, hs.session.root_key);
        for end in 0..hs.bytes.len() {
            assert!(
                process_handshake(&hs.bytes[..end], &keys, 1000, 0).is_err(),
                "accepted prefix {end}, opk={with_opk}"
            );
            checked += 1;
        }
        for byte in 0..=255u8 {
            let mut extra = hs.bytes.clone();
            extra.push(byte);
            assert!(process_handshake(&extra, &keys, 1000, 0).is_err());
            checked += 1;
        }
        // The u64 boundaries must reject stale input, not overflow or panic.
        for now in [0, u64::MAX] {
            assert_eq!(
                process_handshake(&hs.bytes, &keys, now, 0).err(),
                Some(E2eError::Stale)
            );
            checked += 1;
        }
        let flag_at = 1 + MLDSA_PUB + MLKEM_PUB + 8 + 4;
        for flag in 2..=255u8 {
            let mut bad = hs.bytes.clone();
            bad[flag_at] = flag;
            assert_eq!(
                process_handshake(&bad, &keys, 1000, 0).err(),
                Some(E2eError::BadOpkFlag)
            );
            checked += 1;
        }
    }
    println!("rejected malformed/stale cases: {checked}; valid controls: 2");
}
