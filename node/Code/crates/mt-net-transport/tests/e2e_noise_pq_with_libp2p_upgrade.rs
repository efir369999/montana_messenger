#![allow(deprecated)] // exercises the deprecated legacy XK libp2p path on purpose
//! End-to-end test of the libp2p upgrade trait impls for Noise_PQ over real
//! TCP. Exercises the exact upgrade machinery a libp2p SwarmBuilder would
//! invoke when negotiating `/montana/noise-pq/1.0.0`.

use futures::{AsyncReadExt, AsyncWriteExt};
use libp2p::core::upgrade::{InboundConnectionUpgrade, OutboundConnectionUpgrade, UpgradeInfo};
use mt_crypto::{keypair_from_seed, keypair_from_seed_mlkem, KEYPAIR_SEED_SIZE};
use mt_net_transport::noise_pq_upgrade::{
    derive_peer_id, NoisePqInitiatorUpgrade, NoisePqResponderUpgrade,
};
use mt_noise_pq::libp2p_upgrade::{NoisePqInitiatorConfig, NoisePqResponderConfig};
use tokio::net::{TcpListener, TcpStream};
use tokio_util::compat::TokioAsyncReadCompatExt;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn libp2p_upgrade_trait_path_authenticates_peer_id_and_communicates() {
    let (rs_kem_pk, rs_kem_sk) =
        keypair_from_seed_mlkem(&[0x42u8; mt_crypto::MLKEM_SEED_SIZE]).unwrap();
    let (rs_id_pk, rs_id_sk) = keypair_from_seed(&[0x77u8; KEYPAIR_SEED_SIZE]).unwrap();
    let (is_id_pk, is_id_sk) = keypair_from_seed(&[0xAAu8; KEYPAIR_SEED_SIZE]).unwrap();

    let expected_initiator_pid = derive_peer_id(&is_id_pk).unwrap();
    let expected_responder_pid = derive_peer_id(&rs_id_pk).unwrap();

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let responder_task = tokio::spawn(async move {
        let (sock, _peer) = listener.accept().await.unwrap();
        sock.set_nodelay(true).ok();
        let compat = sock.compat();
        let upgrade = NoisePqResponderUpgrade(NoisePqResponderConfig {
            local_static_kem_sk: rs_kem_sk,
            local_id_pk: rs_id_pk,
            local_id_sk: rs_id_sk,
        });
        // multistream-select would pick this protocol; we just pass it through.
        let info = upgrade.protocol_info().next().unwrap();
        let (peer_id, mut stream) = upgrade.upgrade_inbound(compat, info).await.unwrap();
        assert_eq!(peer_id, expected_initiator_pid);

        let mut buf = [0u8; 64];
        let n = stream.read(&mut buf).await.unwrap();
        assert_eq!(&buf[..n], b"hi noise_pq");
        stream.write_all(b"ack noise_pq").await.unwrap();
        stream.flush().await.unwrap();
    });

    let initiator_task = tokio::spawn(async move {
        let sock = TcpStream::connect(addr).await.unwrap();
        sock.set_nodelay(true).ok();
        let compat = sock.compat();
        let upgrade = NoisePqInitiatorUpgrade(NoisePqInitiatorConfig {
            remote_static_kem_pk: rs_kem_pk,
            local_id_pk: is_id_pk,
            local_id_sk: is_id_sk,
        });
        let info = upgrade.protocol_info().next().unwrap();
        let (peer_id, mut stream) = upgrade.upgrade_outbound(compat, info).await.unwrap();
        assert_eq!(peer_id, expected_responder_pid);

        stream.write_all(b"hi noise_pq").await.unwrap();
        stream.flush().await.unwrap();
        let mut buf = [0u8; 64];
        let n = stream.read(&mut buf).await.unwrap();
        assert_eq!(&buf[..n], b"ack noise_pq");
    });

    initiator_task.await.unwrap();
    responder_task.await.unwrap();
}
