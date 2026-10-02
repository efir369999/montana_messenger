//! Integration test for the AEAD-wrapped Noise_PQ stream over a real
//! `tokio::net::TcpStream` pair. Proves AEAD encryption / decryption /
//! per-direction nonce + length framing work over a real socket.

use futures::{AsyncReadExt, AsyncWriteExt};
use mt_noise_pq::stream::NoisePqStream;
use tokio::net::{TcpListener, TcpStream};
use tokio_util::compat::TokioAsyncWriteCompatExt;

async fn run_initiator(addr: std::net::SocketAddr, tx_key: [u8; 32], rx_key: [u8; 32]) {
    let sock = TcpStream::connect(addr).await.unwrap();
    sock.set_nodelay(true).ok();
    let compat = sock.compat_write();
    let mut stream = NoisePqStream::new(compat, tx_key, rx_key);
    stream.write_all(b"hello noise_pq").await.unwrap();
    stream.flush().await.unwrap();
    let mut reply = [0u8; 32];
    let n = stream.read(&mut reply).await.unwrap();
    assert_eq!(&reply[..n], b"world");
}

async fn run_responder(listener: TcpListener, tx_key: [u8; 32], rx_key: [u8; 32]) {
    let (sock, _peer) = listener.accept().await.unwrap();
    sock.set_nodelay(true).ok();
    let compat = sock.compat_write();
    let mut stream = NoisePqStream::new(compat, tx_key, rx_key);
    let mut buf = [0u8; 64];
    let n = stream.read(&mut buf).await.unwrap();
    assert_eq!(&buf[..n], b"hello noise_pq");
    stream.write_all(b"world").await.unwrap();
    stream.flush().await.unwrap();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn aead_roundtrip_over_tcp() {
    let key_i_to_r = [0xA1u8; 32];
    let key_r_to_i = [0xB2u8; 32];

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let responder = tokio::spawn(run_responder(listener, key_r_to_i, key_i_to_r));
    let initiator = tokio::spawn(run_initiator(addr, key_i_to_r, key_r_to_i));

    initiator.await.unwrap();
    responder.await.unwrap();
}
