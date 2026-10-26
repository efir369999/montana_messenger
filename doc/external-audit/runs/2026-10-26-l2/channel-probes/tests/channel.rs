// Characterization of published AUDIT F-1, not a TLS bypass or a phone test.
use mt_crypto::{
    keypair_from_seed, keypair_from_seed_mlkem, MLKEM_CIPHERTEXT_SIZE, PUBLIC_KEY_SIZE,
};
use mt_messenger_e2e::media::{open_blob, seal_blob};
use mt_noise_pq::{
    initiator_receive_msg2, initiator_send_msg1, initiator_send_msg3, responder_receive_msg1,
    responder_receive_msg3, responder_send_msg2, NoisePqError, NoisePqSession,
};

fn channel(initiator: u8, responder: u8) -> (NoisePqSession, NoisePqSession) {
    let (kem_pk, kem_sk) = keypair_from_seed_mlkem(&[responder; 64]).unwrap();
    let (i_pk, i_sk) = keypair_from_seed(&[initiator; 32]).unwrap();
    let (r_pk, r_sk) = keypair_from_seed(&[responder; 32]).unwrap();
    let expected_i = *i_pk.as_bytes();
    let expected_r = *r_pk.as_bytes();
    // Like the app call sites, this takes the key supplied by the connection.
    // No expected peer identity can be passed to these APIs.
    let (one, i) = initiator_send_msg1(&kem_pk, i_sk, i_pk).unwrap();
    let r = responder_receive_msg1(&one, &kem_sk, r_sk, r_pk).unwrap();
    let (two, r) = responder_send_msg2(r).unwrap();
    assert_eq!(
        &two[MLKEM_CIPHERTEXT_SIZE..MLKEM_CIPHERTEXT_SIZE + PUBLIC_KEY_SIZE],
        &expected_r
    );
    let i = initiator_receive_msg2(&two, i).unwrap();
    let (three, i) = initiator_send_msg3(i).unwrap();
    assert_eq!(&three[..PUBLIC_KEY_SIZE], &expected_i);
    let r = responder_receive_msg3(&three, r).unwrap();
    assert_eq!(i.sk_i_to_r, r.sk_i_to_r);
    assert_eq!(i.sk_r_to_i, r.sk_r_to_i);
    (i, r)
}

#[test]
fn two_valid_channels_allow_an_unpinned_middle_to_read_channel_payload() {
    // Rejects the claim that valid handshake signatures authenticate an intended
    // endpoint when its public key is learned from that same untrusted channel.
    let (client, middle_as_server) = channel(0x11, 0xA1);
    let (middle_as_client, server) = channel(0xA2, 0x22);
    assert_ne!(client.transcript_hash, server.transcript_hash);
    assert_ne!(client.sk_i_to_r, server.sk_i_to_r);
    let marker = b"SYNTHETIC_CHANNEL_METADATA_NOT_A_LETTER";
    let left = seal_blob(&client.sk_i_to_r, &[1; 12], marker);
    let read = open_blob(&middle_as_server.sk_i_to_r, &left).unwrap();
    assert_eq!(read, marker);
    let right = seal_blob(&middle_as_client.sk_i_to_r, &[2; 12], &read);
    assert_eq!(open_blob(&server.sk_i_to_r, &right).unwrap(), marker);
    // Inner letter encryption and application registration are not modeled here.
}

#[test]
fn invalid_signature_is_rejected_even_though_the_peer_is_not_pinned() {
    // Control: the finding is missing expected-peer binding, not skipped signature verification.
    let (kem_pk, kem_sk) = keypair_from_seed_mlkem(&[0x33; 64]).unwrap();
    let (i_pk, i_sk) = keypair_from_seed(&[0x44; 32]).unwrap();
    let (r_pk, r_sk) = keypair_from_seed(&[0x55; 32]).unwrap();
    let (one, i) = initiator_send_msg1(&kem_pk, i_sk, i_pk).unwrap();
    let r = responder_receive_msg1(&one, &kem_sk, r_sk, r_pk).unwrap();
    let (mut two, _) = responder_send_msg2(r).unwrap();
    two[MLKEM_CIPHERTEXT_SIZE + PUBLIC_KEY_SIZE] ^= 1;
    assert_eq!(
        initiator_receive_msg2(&two, i).err(),
        Some(NoisePqError::BadResponderSignature)
    );
}
