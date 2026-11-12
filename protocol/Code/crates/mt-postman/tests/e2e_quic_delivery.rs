//! Running test of Stage 1: A->B->ACK through a real QUIC socket and a postman,
//! zero servers of ours. Two independent quinn clients + a postman server
//! talk over the OS loopback (not an in-process channel), which proves the real
//! network path: A --RELAY--> postman --DELIVER--> B --ACK--> postman --> A.

use std::time::Duration;

use mt_crypto::{keypair_from_seed, PublicKey, SecretKey, PUBLIC_KEY_SIZE};
use mt_overlay::frame::{FrameType, MsgId};
use mt_overlay::{overlay_addr, OverlayAddr};
use mt_postman::{PostmanClient, PostmanServer};
use mt_state::{derive_account_id, SUITE_MLDSA65};

fn ident(seed: u8) -> ([u8; PUBLIC_KEY_SIZE], SecretKey, OverlayAddr) {
    let (pk, sk): (PublicKey, SecretKey) = keypair_from_seed(&[seed; 32]).unwrap();
    let pkb = *pk.as_bytes();
    let addr = overlay_addr(&derive_account_id(SUITE_MLDSA65, &pkb));
    (pkb, sk, addr)
}

async fn with_timeout<F: std::future::Future>(f: F) -> F::Output {
    tokio::time::timeout(Duration::from_secs(10), f)
        .await
        .expect("operation must not hang for more than 10s")
}

#[tokio::test]
async fn a_to_b_to_ack_over_real_quic() {
    // Postman on loopback, port 0 (the OS picks the port): "the box you hold yourself".
    let server = PostmanServer::bind("127.0.0.1:0".parse().unwrap())
        .await
        .unwrap();
    let postman_addr = server.local_addr().unwrap();
    tokio::spawn(server.run());

    let (pk_a, sk_a, addr_a) = ident(0xA1);
    let (pk_b, sk_b, addr_b) = ident(0xB2);

    // A and B connect to the postman and register overlay_addr via ML-DSA.
    let client_a = with_timeout(PostmanClient::connect(postman_addr, pk_a, &sk_a))
        .await
        .expect("A registers");
    let mut client_b = with_timeout(PostmanClient::connect(postman_addr, pk_b, &sk_b))
        .await
        .expect("B registers");

    assert_eq!(client_a.overlay(), addr_a);
    assert_eq!(client_b.overlay(), addr_b);

    // A sends RELAY->B with an opaque "E2E envelope".
    let msg_id: MsgId = [0x77; 16];
    let envelope = b"sealed-e2e-envelope-A-to-B".to_vec();
    with_timeout(client_a.send_relay(addr_b, msg_id, envelope.clone()))
        .await
        .expect("A sends RELAY");

    // B receives DELIVER (same msg_id, same payload; the postman did not touch the payload).
    let delivered = with_timeout(client_b.recv())
        .await
        .expect("B receives DELIVER");
    assert_eq!(delivered.frame_type, FrameType::Deliver);
    assert_eq!(delivered.msg_id, msg_id);
    assert_eq!(delivered.dst_overlay, addr_b);
    assert_eq!(delivered.payload, envelope);

    // B replies ACK for the same msg_id; the postman routes it back to A.
    with_timeout(client_b.send_ack(delivered.src_overlay, msg_id))
        .await
        .expect("B sends ACK");

    let mut client_a = client_a;
    let ack = with_timeout(client_a.recv()).await.expect("A receives ACK");
    assert_eq!(ack.frame_type, FrameType::Ack);
    assert_eq!(ack.msg_id, msg_id);
    assert_eq!(ack.dst_overlay, addr_a);
    assert!(ack.payload.is_empty());
}

#[tokio::test]
async fn relay_to_offline_b_does_not_reach_a_as_deliver() {
    // B is offline (not connected): the postman buffers (Stage 2), A gets no false DELIVER.
    let server = PostmanServer::bind("127.0.0.1:0".parse().unwrap())
        .await
        .unwrap();
    let postman_addr = server.local_addr().unwrap();
    tokio::spawn(server.run());

    let (pk_a, sk_a, _addr_a) = ident(0xA1);
    let (_pk_b, _sk_b, addr_b) = ident(0xB2);

    let mut client_a = with_timeout(PostmanClient::connect(postman_addr, pk_a, &sk_a))
        .await
        .expect("A registers");

    with_timeout(client_a.send_relay(addr_b, [0x01; 16], b"x".to_vec()))
        .await
        .expect("A sends RELAY to offline B");

    // A must receive nothing (no echo, no false DELIVER) within a reasonable window.
    let got = tokio::time::timeout(Duration::from_millis(700), client_a.recv()).await;
    assert!(
        got.is_err(),
        "A must not receive anything while B is offline at Stage 1"
    );
}

#[tokio::test]
async fn duplicate_msg_id_delivered_once() {
    // §396: A sends one msg_id twice, B receives DELIVER exactly once.
    let server = PostmanServer::bind("127.0.0.1:0".parse().unwrap())
        .await
        .unwrap();
    let postman_addr = server.local_addr().unwrap();
    tokio::spawn(server.run());

    let (pk_a, sk_a, _addr_a) = ident(0xA1);
    let (pk_b, sk_b, addr_b) = ident(0xB2);

    let client_a = with_timeout(PostmanClient::connect(postman_addr, pk_a, &sk_a))
        .await
        .expect("A registers");
    let mut client_b = with_timeout(PostmanClient::connect(postman_addr, pk_b, &sk_b))
        .await
        .expect("B registers");

    let msg_id: MsgId = [0x55; 16];
    for _ in 0..2 {
        with_timeout(client_a.send_relay(addr_b, msg_id, b"dup".to_vec()))
            .await
            .expect("A sends RELAY (duplicate)");
    }

    let first = with_timeout(client_b.recv()).await.expect("first DELIVER");
    assert_eq!(first.msg_id, msg_id);
    // The second DELIVER does not arrive: dropped by dedup.
    let second = tokio::time::timeout(Duration::from_millis(700), client_b.recv()).await;
    assert!(
        second.is_err(),
        "duplicate msg_id must be dropped at the receiver"
    );
}
