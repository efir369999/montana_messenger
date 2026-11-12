//! End-to-end test: full Noise_PQ handshake over TCP, then AEAD-encrypted
//! application messages over the same socket. Validates that the entire
//! post-quantum transport works end-to-end with no classical primitive.

use futures::{AsyncReadExt, AsyncWriteExt};
use mt_crypto::{keypair_from_seed, keypair_from_seed_mlkem, KEYPAIR_SEED_SIZE};
use mt_noise_pq::stream::NoisePqStream;
use mt_noise_pq::*;
use tokio::io::{AsyncReadExt as TokioRead, AsyncWriteExt as TokioWrite};
use tokio::net::{TcpListener, TcpStream};
use tokio_util::compat::TokioAsyncReadCompatExt;

async fn run_initiator(
    addr: std::net::SocketAddr,
    rs_kem_pk: mt_crypto::MlkemPublicKey,
    is_id_pk: mt_crypto::PublicKey,
    is_id_sk: mt_crypto::SecretKey,
) {
    let mut sock = TcpStream::connect(addr).await.unwrap();
    sock.set_nodelay(true).ok();

    // Handshake msg1.
    let (msg1, init_state) = initiator_send_msg1(&rs_kem_pk, is_id_sk, is_id_pk).unwrap();
    sock.write_all(&msg1).await.unwrap();

    // Read msg2.
    let mut msg2 = vec![0u8; NOISE_PQ_MSG2_SIZE];
    sock.read_exact(&mut msg2).await.unwrap();
    let init_after_msg2 = initiator_receive_msg2(&msg2, init_state).unwrap();

    // Send msg3.
    let (msg3, session) = initiator_send_msg3(init_after_msg2).unwrap();
    sock.write_all(&msg3).await.unwrap();

    // Switch to AEAD stream and exchange application data.
    let compat = sock.compat();
    let mut stream = NoisePqStream::new(compat, session.sk_i_to_r, session.sk_r_to_i);
    stream.write_all(b"montana noise_pq hello").await.unwrap();
    stream.flush().await.unwrap();

    let mut reply = [0u8; 64];
    let n = stream.read(&mut reply).await.unwrap();
    assert_eq!(&reply[..n], b"montana noise_pq ack");
}

async fn run_responder(
    listener: TcpListener,
    rs_kem_sk: mt_crypto::MlkemSecretKey,
    rs_id_pk: mt_crypto::PublicKey,
    rs_id_sk: mt_crypto::SecretKey,
) {
    let (mut sock, _peer) = listener.accept().await.unwrap();
    sock.set_nodelay(true).ok();

    // Read msg1.
    let mut msg1 = vec![0u8; NOISE_PQ_MSG1_SIZE];
    sock.read_exact(&mut msg1).await.unwrap();
    let resp_state = responder_receive_msg1(&msg1, &rs_kem_sk, rs_id_sk, rs_id_pk).unwrap();

    // Send msg2.
    let (msg2, resp_after_msg2) = responder_send_msg2(resp_state).unwrap();
    sock.write_all(&msg2).await.unwrap();

    // Read msg3.
    let mut msg3 = vec![0u8; NOISE_PQ_MSG3_SIZE];
    sock.read_exact(&mut msg3).await.unwrap();
    let session = responder_receive_msg3(&msg3, resp_after_msg2).unwrap();

    // Switch to AEAD stream. Note: responder's TX is i2r direction's RX
    // (mirror of initiator's TX assignment).
    let compat = sock.compat();
    let mut stream = NoisePqStream::new(compat, session.sk_r_to_i, session.sk_i_to_r);
    let mut buf = [0u8; 128];
    let n = stream.read(&mut buf).await.unwrap();
    assert_eq!(&buf[..n], b"montana noise_pq hello");
    stream.write_all(b"montana noise_pq ack").await.unwrap();
    stream.flush().await.unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn full_handshake_then_aead_app_messages_over_tcp() {
    let (rs_kem_pk, rs_kem_sk) =
        keypair_from_seed_mlkem(&[0x42u8; mt_crypto::MLKEM_SEED_SIZE]).unwrap();
    let (rs_id_pk, rs_id_sk) = keypair_from_seed(&[0x77u8; KEYPAIR_SEED_SIZE]).unwrap();
    let (is_id_pk, is_id_sk) = keypair_from_seed(&[0xAAu8; KEYPAIR_SEED_SIZE]).unwrap();

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let responder = tokio::spawn(run_responder(listener, rs_kem_sk, rs_id_pk, rs_id_sk));
    let initiator = tokio::spawn(run_initiator(addr, rs_kem_pk, is_id_pk, is_id_sk));

    initiator.await.unwrap();
    responder.await.unwrap();
}
