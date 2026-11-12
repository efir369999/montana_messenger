//! Phase 3 acceptance test for the Noise_PQ handshake: an initiator and a
//! responder exchange the three messages over a real `tokio::net::TcpStream`
//! loopback pair, and both ends derive byte-identical session keys.
//!
//! This validates that the wire bytes flow correctly through an async socket
//! (no framing assumption beyond size-prefixed fixed-length messages) and
//! that the handshake works in the actual transport environment a Montana
//! node would face. Full libp2p Swarm integration is the next step
//! (Phase 3 — libp2p custom upgrade) and is tracked in DEV-014.

use mt_crypto::{keypair_from_seed, keypair_from_seed_mlkem, KEYPAIR_SEED_SIZE};
use mt_noise_pq::*;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

async fn run_initiator(
    addr: std::net::SocketAddr,
    rs_kem_pk: mt_crypto::MlkemPublicKey,
    is_id_pk: mt_crypto::PublicKey,
    is_id_sk: mt_crypto::SecretKey,
) -> ([u8; 32], [u8; 32], [u8; 32]) {
    let mut sock = TcpStream::connect(addr).await.unwrap();
    sock.set_nodelay(true).ok();

    let (msg1, init_state) = initiator_send_msg1(&rs_kem_pk, is_id_sk, is_id_pk).unwrap();
    sock.write_all(&msg1).await.unwrap();

    let mut msg2 = vec![0u8; NOISE_PQ_MSG2_SIZE];
    sock.read_exact(&mut msg2).await.unwrap();

    let init_after_msg2 = initiator_receive_msg2(&msg2, init_state).unwrap();
    let (msg3, session) = initiator_send_msg3(init_after_msg2).unwrap();
    sock.write_all(&msg3).await.unwrap();
    sock.shutdown().await.ok();

    (
        session.sk_i_to_r,
        session.sk_r_to_i,
        session.transcript_hash,
    )
}

async fn run_responder(
    listener: TcpListener,
    rs_kem_sk: mt_crypto::MlkemSecretKey,
    rs_id_pk: mt_crypto::PublicKey,
    rs_id_sk: mt_crypto::SecretKey,
) -> ([u8; 32], [u8; 32], [u8; 32]) {
    let (mut sock, _peer) = listener.accept().await.unwrap();
    sock.set_nodelay(true).ok();

    let mut msg1 = vec![0u8; NOISE_PQ_MSG1_SIZE];
    sock.read_exact(&mut msg1).await.unwrap();

    let resp_state = responder_receive_msg1(&msg1, &rs_kem_sk, rs_id_sk, rs_id_pk).unwrap();
    let (msg2, resp_after_msg2) = responder_send_msg2(resp_state).unwrap();
    sock.write_all(&msg2).await.unwrap();

    let mut msg3 = vec![0u8; NOISE_PQ_MSG3_SIZE];
    sock.read_exact(&mut msg3).await.unwrap();

    let session = responder_receive_msg3(&msg3, resp_after_msg2).unwrap();
    sock.shutdown().await.ok();

    (
        session.sk_i_to_r,
        session.sk_r_to_i,
        session.transcript_hash,
    )
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tcp_loopback_full_handshake() {
    // Fixed identities so the test is reproducible across runs.
    let (rs_kem_pk, rs_kem_sk) =
        keypair_from_seed_mlkem(&[0x42u8; mt_crypto::MLKEM_SEED_SIZE]).unwrap();
    let (rs_id_pk, rs_id_sk) = keypair_from_seed(&[0x77u8; KEYPAIR_SEED_SIZE]).unwrap();
    let (is_id_pk, is_id_sk) = keypair_from_seed(&[0xAAu8; KEYPAIR_SEED_SIZE]).unwrap();

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let responder = tokio::spawn(run_responder(listener, rs_kem_sk, rs_id_pk, rs_id_sk));
    let initiator = tokio::spawn(run_initiator(addr, rs_kem_pk, is_id_pk, is_id_sk));

    let init_out = initiator.await.unwrap();
    let resp_out = responder.await.unwrap();

    assert_eq!(init_out.0, resp_out.0, "sk_i_to_r mismatch over TCP");
    assert_eq!(init_out.1, resp_out.1, "sk_r_to_i mismatch over TCP");
    assert_eq!(init_out.2, resp_out.2, "transcript_hash mismatch over TCP");
}
