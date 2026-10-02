//! Round-trip test for the Noise_PQ XX handshake drive with length
//! obfuscation. The initiator and responder complete the padded handshake
//! and exchange an application message over the AEAD stream. The loop runs
//! several times so the random padding length varies between runs.

use futures::{AsyncReadExt, AsyncWriteExt};
use mt_crypto::{keypair_from_seed, KEYPAIR_SEED_SIZE};
use mt_noise_pq::xx_libp2p_upgrade::{xx_initiator_drive, xx_responder_drive};
use std::sync::Arc;
use tokio_util::compat::TokioAsyncReadCompatExt;

#[tokio::test]
async fn xx_drive_padded_handshake_roundtrips() {
    for i in 0..8u8 {
        let (i_pk, i_sk) = keypair_from_seed(&[i.wrapping_add(1); KEYPAIR_SEED_SIZE]).unwrap();
        let (r_pk, r_sk) = keypair_from_seed(&[i.wrapping_add(101); KEYPAIR_SEED_SIZE]).unwrap();

        let (a, b) = tokio::io::duplex(1 << 16);
        let a = a.compat();
        let b = b.compat();
        let i_sk = Arc::new(i_sk);
        let r_sk = Arc::new(r_sk);

        let init = tokio::spawn(async move {
            let (_sess, mut s) = xx_initiator_drive(a, i_pk, i_sk).await.unwrap();
            s.write_all(b"ping").await.unwrap();
            s.flush().await.unwrap();
            let mut buf = [0u8; 4];
            s.read_exact(&mut buf).await.unwrap();
            buf
        });
        let resp = tokio::spawn(async move {
            let (_sess, mut s) = xx_responder_drive(b, r_pk, r_sk).await.unwrap();
            let mut buf = [0u8; 4];
            s.read_exact(&mut buf).await.unwrap();
            s.write_all(b"pong").await.unwrap();
            s.flush().await.unwrap();
            buf
        });

        assert_eq!(&init.await.unwrap(), b"pong", "initiator receives pong");
        assert_eq!(&resp.await.unwrap(), b"ping", "responder receives ping");
    }
}
