//! Client (phone, Stage 1; TCP+TLS transport, spec §152). Connect to the postman ->
//! register overlay_addr (RegHello/RegChallenge/RegProof, ML-DSA-65) -> send RELAY,
//! receive DELIVER/ACK. Persistent connection: split into a reader (incoming -> recv() channel)
//! + a writer (outgoing frames under an async lock).

use std::net::SocketAddr;
use std::sync::Arc;

use rustls::pki_types::ServerName;
use thiserror::Error;
use tokio::io::{split, WriteHalf};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, Mutex as AsyncMutex};
use tokio_rustls::client::TlsStream;

use mt_crypto::{SecretKey, PUBLIC_KEY_SIZE};
use mt_overlay::challenge::{sign_registration, Nonce, NONCE_SIZE};
use mt_overlay::dedup::DedupWindow;
use mt_overlay::frame::{FrameType, MsgId, OverlayFrame};
use mt_overlay::prologue::{decode_reg_challenge, encode_reg_hello, encode_reg_proof};
use mt_overlay::{overlay_addr, OverlayAddr};
use mt_state::{derive_account_id, SUITE_MLDSA65};

use crate::config::{tls_connector, ConfigError, STAND_SNI};
use crate::wire::{channel_hash, read_fixed, recv_frame, send_frame, write_fixed, WireError};

const REG_OK: u8 = 0x01;

#[derive(Debug, Error)]
pub enum ClientError {
    #[error("config: {0}")]
    Config(#[from] ConfigError),
    #[error("endpoint io: {0}")]
    Io(#[from] std::io::Error),
    #[error("wire: {0}")]
    Wire(#[from] WireError),
    #[error("crypto: {0}")]
    Crypto(#[from] mt_crypto::CryptoError),
    #[error("connection closed")]
    Closed,
    #[error("malformed challenge from postman")]
    MalformedChallenge,
    #[error("direct registration on a foreign host is forbidden (§534 self-host only); use register_via_courier")]
    ForeignHostRegistration,
    #[error("decode: {0:?}")]
    Decode(mt_overlay::frame::FrameError),
    #[error("postman rejected registration")]
    Rejected,
}

type ClientStream = TlsStream<TcpStream>;

pub struct PostmanClient {
    writer: Arc<AsyncMutex<WriteHalf<ClientStream>>>,
    overlay: OverlayAddr,
    incoming: mpsc::Receiver<OverlayFrame>,
}

impl PostmanClient {
    /// Connect to the postman and register overlay_addr.
    pub async fn connect(
        server: SocketAddr,
        account_pubkey: [u8; PUBLIC_KEY_SIZE],
        account_sk: &SecretKey,
    ) -> Result<Self, ClientError> {
        let connector = tls_connector()?;
        let tcp = TcpStream::connect(server).await?;
        tcp.set_nodelay(true).ok();
        let sni = ServerName::try_from(STAND_SNI)
            .map_err(|_| ClientError::Closed)?
            .to_owned();
        let mut tls = connector.connect(sni, tcp).await?;

        // Handshake over the duplex stream (before the split).
        write_fixed(&mut tls, &encode_reg_hello(&account_pubkey)).await?;

        let mut chal = [0u8; NONCE_SIZE];
        read_fixed(&mut tls, &mut chal).await?;
        let nonce: Nonce =
            decode_reg_challenge(&chal).map_err(|_| ClientError::MalformedChallenge)?;

        let ch = channel_hash(tls.get_ref().1)?;
        let account_id = derive_account_id(SUITE_MLDSA65, &account_pubkey);
        let overlay = overlay_addr(&account_id);
        let sig = sign_registration(account_sk, &overlay, &nonce, &ch)?;
        write_fixed(&mut tls, &encode_reg_proof(sig.as_bytes())).await?;

        let mut ok = [0u8; 1];
        read_fixed(&mut tls, &mut ok).await?;
        if ok[0] != REG_OK {
            return Err(ClientError::Rejected);
        }

        // Split: the reader pumps incoming frames into the channel, the writer sends outgoing ones under a lock.
        let (mut reader, writer) = split(tls);
        let (tx, rx) = mpsc::channel(64);
        tokio::spawn(async move {
            // Stage 1 step 4 (§396): dedup of incoming frames by msg_id with a sliding window.
            let mut dedup = DedupWindow::default();
            while let Ok(bytes) = recv_frame(&mut reader).await {
                if let Ok(f) = OverlayFrame::decode(&bytes) {
                    if !dedup.check_and_insert(&f.msg_id) {
                        continue; // duplicate -- drop
                    }
                    if tx.send(f).await.is_err() {
                        break;
                    }
                }
            }
        });

        Ok(Self {
            writer: Arc::new(AsyncMutex::new(writer)),
            overlay,
            incoming: rx,
        })
    }

    pub fn overlay(&self) -> OverlayAddr {
        self.overlay
    }

    /// Send RELAY to recipient dst with an opaque E2E payload.
    pub async fn send_relay(
        &self,
        dst: OverlayAddr,
        msg_id: MsgId,
        payload: Vec<u8>,
    ) -> Result<(), ClientError> {
        self.send_frame_typed(FrameType::Relay, dst, msg_id, payload)
            .await
    }

    /// Reply ACK to the sender dst with the same msg_id (empty payload).
    pub async fn send_ack(&self, dst: OverlayAddr, msg_id: MsgId) -> Result<(), ClientError> {
        self.send_frame_typed(FrameType::Ack, dst, msg_id, Vec::new())
            .await
    }

    async fn send_frame_typed(
        &self,
        frame_type: FrameType,
        dst: OverlayAddr,
        msg_id: MsgId,
        payload: Vec<u8>,
    ) -> Result<(), ClientError> {
        let f = OverlayFrame {
            frame_type,
            dst_overlay: dst,
            src_overlay: self.overlay,
            msg_id,
            payload,
        };
        let mut w = self.writer.lock().await;
        send_frame(&mut *w, &f.to_bytes()).await?;
        Ok(())
    }

    /// Wait for the next incoming frame (DELIVER or ACK) from the postman.
    pub async fn recv(&mut self) -> Option<OverlayFrame> {
        self.incoming.recv().await
    }
}
