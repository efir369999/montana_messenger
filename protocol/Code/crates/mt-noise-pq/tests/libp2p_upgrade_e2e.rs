#![allow(deprecated)] // exercises the deprecated legacy XK libp2p path on purpose
//! End-to-end test of the libp2p-style upgrade scaffolding: initiator and
//! responder use `initiator_drive` / `responder_drive` which mirror the
//! shape that `libp2p::core::upgrade::{Inbound,Outbound}ConnectionUpgrade`
//! expect (async function from socket + config → (RemoteIdentity, Stream)).

use futures::{AsyncReadExt, AsyncWriteExt};
use mt_crypto::{keypair_from_seed, keypair_from_seed_mlkem, KEYPAIR_SEED_SIZE};
use mt_noise_pq::libp2p_upgrade::{
    initiator_drive, responder_drive, NoisePqInitiatorConfig, NoisePqResponderConfig,
};
use tokio::net::{TcpListener, TcpStream};
use tokio_util::compat::TokioAsyncReadCompatExt;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn libp2p_drive_pair_authenticates_and_communicates() {
    let (rs_kem_pk, rs_kem_sk) =
        keypair_from_seed_mlkem(&[0x42u8; mt_crypto::MLKEM_SEED_SIZE]).unwrap();
    let (rs_id_pk, rs_id_sk) = keypair_from_seed(&[0x77u8; KEYPAIR_SEED_SIZE]).unwrap();
    let (is_id_pk, is_id_sk) = keypair_from_seed(&[0xAAu8; KEYPAIR_SEED_SIZE]).unwrap();
    let is_id_pk_for_assert = is_id_pk.clone();
    let rs_id_pk_for_assert = rs_id_pk.clone();

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let responder_task = tokio::spawn(async move {
        let (sock, _peer) = listener.accept().await.unwrap();
        sock.set_nodelay(true).ok();
        let compat = sock.compat();
        let config = NoisePqResponderConfig {
            local_static_kem_sk: rs_kem_sk,
            local_id_pk: rs_id_pk,
            local_id_sk: rs_id_sk,
        };
        let (remote_id, mut stream) = responder_drive(compat, config).await.unwrap();

        // Verify that the responder learned the initiator's authenticated
        // ML-DSA-65 identity from the handshake.
        assert_eq!(
            remote_id.mldsa65_pubkey.as_bytes(),
            is_id_pk_for_assert.as_bytes()
        );

        let mut buf = [0u8; 64];
        let n = stream.read(&mut buf).await.unwrap();
        assert_eq!(&buf[..n], b"hi from initiator");
        stream.write_all(b"hi from responder").await.unwrap();
        stream.flush().await.unwrap();
    });

    let initiator_task = tokio::spawn(async move {
        let sock = TcpStream::connect(addr).await.unwrap();
        sock.set_nodelay(true).ok();
        let compat = sock.compat();
        let config = NoisePqInitiatorConfig {
            remote_static_kem_pk: rs_kem_pk,
            local_id_pk: is_id_pk,
            local_id_sk: is_id_sk,
        };
        let (remote_id, mut stream) = initiator_drive(compat, config).await.unwrap();

        // Verify that the initiator learned the responder's authenticated
        // ML-DSA-65 identity from the handshake.
        assert_eq!(
            remote_id.mldsa65_pubkey.as_bytes(),
            rs_id_pk_for_assert.as_bytes()
        );

        stream.write_all(b"hi from initiator").await.unwrap();
        stream.flush().await.unwrap();
        let mut buf = [0u8; 64];
        let n = stream.read(&mut buf).await.unwrap();
        assert_eq!(&buf[..n], b"hi from responder");
    });

    initiator_task.await.unwrap();
    responder_task.await.unwrap();
}
