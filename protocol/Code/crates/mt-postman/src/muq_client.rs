//! MUQ client (Stage 2; TCP+TLS transport, spec §152). Every operation is a fresh short
//! TCP+TLS connection (unlinkable: one connection per operation, the node sees only an ephemeral queue key,
//! not account_id). Recipient: register_queue + subscribe; sender: deposit (two-hop).

use std::net::SocketAddr;

use rustls::pki_types::ServerName;
use tokio::net::TcpStream;
use tokio_rustls::client::TlsStream;
use tokio_rustls::TlsConnector;

use mt_crypto::{seal_to, MlkemPublicKey, SecretKey};
use mt_overlay::challenge::NONCE_SIZE;
use mt_overlay::erasure::{rs_reconstruct, rs_split};
use mt_overlay::frame::MsgId;
use mt_overlay::muq::{
    sign_deposit, sign_subscribe_relay, HostDeposit, ProxyForward, Queue, QueueId, QueueResp,
    QueueSubscribe, ReceiveProxy,
};
use mt_overlay::OverlayAddr;

use crate::client::ClientError;
use crate::config::{tls_connector, STAND_SNI};
use crate::muq::{
    TAG_PROXY_FORWARD, TAG_PROXY_REGISTER, TAG_QUEUE_REGISTER, TAG_RECEIVE_ACK, TAG_RECEIVE_NONCE,
    TAG_RECEIVE_PROXY,
};
use crate::wire::{read_fixed, recv_frame, send_frame, write_fixed};

const OK: u8 = 0x01;

/// Open a fresh TCP+TLS stream to the postman `addr`.
async fn open_stream(
    addr: SocketAddr,
    connector: &TlsConnector,
) -> Result<TlsStream<TcpStream>, ClientError> {
    let tcp = TcpStream::connect(addr)
        .await
        .map_err(|_| ClientError::Closed)?;
    tcp.set_nodelay(true).ok();
    let sni = ServerName::try_from(STAND_SNI)
        .map_err(|_| ClientError::Closed)?
        .to_owned();
    connector
        .connect(sni, tcp)
        .await
        .map_err(|_| ClientError::Closed)
}

/// Node hello: connect to a node, get its capability (host_kem 1184 + send_id 32).
/// The sender finds a node via mDNS, calls hello -> deposits without a card (serverless automaton).
pub async fn node_hello(addr: SocketAddr) -> Result<([u8; 1184], [u8; 32]), ClientError> {
    let connector = tls_connector().map_err(|_| ClientError::Closed)?;
    let mut st = open_stream(addr, &connector).await?;
    write_fixed(&mut st, &[crate::muq::TAG_NODE_HELLO]).await?;
    let mut kem = [0u8; 1184];
    read_fixed(&mut st, &mut kem).await?;
    let mut sid = [0u8; 32];
    read_fixed(&mut st, &mut sid).await?;
    Ok((kem, sid))
}

pub struct MuqClient {
    addr: SocketAddr,
    connector: TlsConnector,
}

impl MuqClient {
    /// Connect to a MUQ node (host or proxy). Validates reachability with one TCP+TLS
    /// handshake (FFI connect fails on an unreachable postman), then every operation is a
    /// fresh connection.
    pub async fn connect(server: SocketAddr) -> Result<Self, ClientError> {
        let connector = tls_connector().map_err(|_| ClientError::Closed)?;
        // Validating handshake: closed at once (the server waits for the tag, gets EOF, drops).
        let _probe = open_stream(server, &connector).await?;
        Ok(Self {
            addr: server,
            connector,
        })
    }

    async fn open(&self) -> Result<TlsStream<TcpStream>, ClientError> {
        open_stream(self.addr, &self.connector).await
    }

    /// The recipient registers a queue on the host. Returns true on ok.
    pub async fn register_queue(&self, q: &Queue) -> Result<bool, ClientError> {
        let mut st = self.open().await?;
        write_fixed(&mut st, &[TAG_QUEUE_REGISTER]).await?;
        write_fixed(&mut st, &q.to_bytes()).await?;
        let mut ack = [0u8; 1];
        read_fixed(&mut st, &mut ack).await?;
        Ok(ack[0] == OK)
    }

    /// The sender places a deposit via an entry proxy (two-hop; sealed is opaque to the proxy).
    pub async fn deposit_via_proxy(&self, pf: &ProxyForward) -> Result<bool, ClientError> {
        let mut st = self.open().await?;
        write_fixed(&mut st, &[TAG_PROXY_FORWARD]).await?;
        send_frame(&mut st, &pf.to_bytes()).await?;
        let mut ack = [0u8; 1];
        read_fixed(&mut st, &mut ack).await?;
        Ok(ack[0] == OK)
    }

    /// Relay registration of a queue on a foreign host via a courier (the host sees the courier, not us).
    /// The queue is sealed with ML-KEM to the host -- the courier is crypto-blind to recv_id/recv_pubkey.
    pub async fn register_via_courier(
        &self,
        host_overlay: OverlayAddr,
        host_kem_pk: &MlkemPublicKey,
        q: &Queue,
    ) -> Result<bool, ClientError> {
        let sealed = seal_to(host_kem_pk, &q.to_bytes()).map_err(|_| ClientError::Rejected)?;
        let pf = ProxyForward {
            host_addr: host_overlay,
            sealed,
        };
        let mut st = self.open().await?;
        write_fixed(&mut st, &[TAG_PROXY_REGISTER]).await?;
        send_frame(&mut st, &pf.to_bytes()).await?;
        let mut ack = [0u8; 1];
        read_fixed(&mut st, &mut ack).await?;
        Ok(ack[0] == OK)
    }

    /// Relay fetch via a courier (the host sees the courier, not us).
    pub async fn subscribe_via_courier(
        &self,
        host_overlay: OverlayAddr,
        host_kem_pk: &MlkemPublicKey,
        recv_id: QueueId,
        recv_sk: &SecretKey,
    ) -> Result<QueueResp, ClientError> {
        // DEV-050(c) §478: first a host-issued nonce (via the courier), then the fetch signature over it.
        let nonce = self
            .request_nonce_via_courier(host_overlay, host_kem_pk, recv_id)
            .await?;
        let sig = sign_subscribe_relay(recv_sk, &recv_id, &nonce)?;
        let sub = QueueSubscribe {
            recv_id,
            nonce,
            sig: *sig.as_bytes(),
        };
        let sealed = seal_to(host_kem_pk, &sub.to_bytes()).map_err(|_| ClientError::Rejected)?;
        let rp = ReceiveProxy {
            host_addr: host_overlay,
            sealed,
        };
        let mut st = self.open().await?;
        write_fixed(&mut st, &[TAG_RECEIVE_PROXY]).await?;
        send_frame(&mut st, &rp.to_bytes()).await?;
        let bytes = recv_frame(&mut st).await?;
        QueueResp::decode(&bytes).map_err(ClientError::Decode)
    }

    /// DEV-050(c) §478: the recipient requests from the host (via the courier) a fresh host-issued
    /// nonce for recv_id before the fetch. The courier is crypto-blind (sealed recv_id to the host ML-KEM).
    async fn request_nonce_via_courier(
        &self,
        host_overlay: OverlayAddr,
        host_kem_pk: &MlkemPublicKey,
        recv_id: QueueId,
    ) -> Result<[u8; NONCE_SIZE], ClientError> {
        let sealed = seal_to(host_kem_pk, &recv_id).map_err(|_| ClientError::Rejected)?;
        let pf = ProxyForward {
            host_addr: host_overlay,
            sealed,
        };
        let mut st = self.open().await?;
        write_fixed(&mut st, &[TAG_RECEIVE_NONCE]).await?;
        send_frame(&mut st, &pf.to_bytes()).await?;
        let mut nonce = [0u8; NONCE_SIZE];
        read_fixed(&mut st, &mut nonce).await?;
        Ok(nonce)
    }

    /// DEV-049(a) §593: confirm receipt -- the host drops the queue buffer (drop-on-ack).
    /// ack is authenticated like a fetch -- host-issued nonce + recv_key signature.
    pub async fn ack_via_courier(
        &self,
        host_overlay: OverlayAddr,
        host_kem_pk: &MlkemPublicKey,
        recv_id: QueueId,
        recv_sk: &SecretKey,
    ) -> Result<bool, ClientError> {
        let nonce = self
            .request_nonce_via_courier(host_overlay, host_kem_pk, recv_id)
            .await?;
        let sig = sign_subscribe_relay(recv_sk, &recv_id, &nonce)?;
        let sub = QueueSubscribe {
            recv_id,
            nonce,
            sig: *sig.as_bytes(),
        };
        let sealed = seal_to(host_kem_pk, &sub.to_bytes()).map_err(|_| ClientError::Rejected)?;
        let pf = ProxyForward {
            host_addr: host_overlay,
            sealed,
        };
        let mut st = self.open().await?;
        write_fixed(&mut st, &[TAG_RECEIVE_ACK]).await?;
        send_frame(&mut st, &pf.to_bytes()).await?;
        let mut ack = [0u8; 1];
        read_fixed(&mut st, &mut ack).await?;
        Ok(ack[0] == crate::muq::ack_ok())
    }

    /// DEV-049(b) §201/§508: RS(k,n) fan-out -- splits `ct` into `n` shards, deposits one
    /// to each of the `n` hosts (two-hop to each). Returns the number of successful deposits.
    #[allow(clippy::too_many_arguments)]
    pub async fn deposit_erasure(
        &self,
        hosts: &[(OverlayAddr, MlkemPublicKey)],
        k: usize,
        send_id: QueueId,
        send_sk: &SecretKey,
        msg_id: MsgId,
        ct: &[u8],
    ) -> Result<usize, ClientError> {
        let n = hosts.len();
        let shards = rs_split(ct, k, n).map_err(|_| ClientError::Rejected)?;
        let mut ok = 0usize;
        for (i, ((overlay, kem), shard)) in hosts.iter().zip(shards.iter()).enumerate() {
            let mut nonce = [0u8; NONCE_SIZE];
            getrandom::getrandom(&mut nonce).map_err(|_| ClientError::Rejected)?;
            let sig = sign_deposit(send_sk, &send_id, &msg_id, &nonce)
                .map_err(|_| ClientError::Rejected)?;
            let hd = HostDeposit {
                send_id,
                msg_id,
                ttl_windows: 240,
                shard_index: i as u8,
                shard_total: n as u8,
                nonce,
                ct: shard.clone(),
                sig: *sig.as_bytes(),
            };
            let sealed = seal_to(kem, &hd.to_bytes()).map_err(|_| ClientError::Rejected)?;
            let pf = ProxyForward {
                host_addr: *overlay,
                sealed,
            };
            if self.deposit_via_proxy(&pf).await.unwrap_or(false) {
                ok += 1;
            }
        }
        Ok(ok)
    }

    /// DEV-049(b): collects shards from `n` hosts and reconstructs from any `k` (RS).
    pub async fn fetch_erasure(
        &self,
        hosts: &[(OverlayAddr, MlkemPublicKey)],
        k: usize,
        recv_id: QueueId,
        recv_sk: &SecretKey,
    ) -> Result<Option<Vec<u8>>, ClientError> {
        let n = hosts.len();
        let mut shards: Vec<Option<Vec<u8>>> = vec![None; n];
        let mut got = 0usize;
        for (overlay, kem) in hosts {
            if let Ok(resp) = self
                .subscribe_via_courier(*overlay, kem, recv_id, recv_sk)
                .await
            {
                if let Some(item) = resp.items.first() {
                    let idx = item.shard_index as usize;
                    if idx < n && shards[idx].is_none() {
                        shards[idx] = Some(item.ct.clone());
                        got += 1;
                    }
                }
            }
        }
        if got < k {
            return Ok(None);
        }
        rs_reconstruct(shards, k, n)
            .map(Some)
            .map_err(|_| ClientError::Rejected)
    }
}
