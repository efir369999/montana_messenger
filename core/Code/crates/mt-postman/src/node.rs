//! Node -- the single Montana node entity (P2P Network Stage 3; TCP+TLS transport, spec §152).
//! A node SIMULTANEOUSLY listens (host keeps queues + courier relays foreign traffic) AND initiates
//! connections (client -- sends/receives its own) -- through one indistinguishable door. There is no split
//! into "postman server" and "client": availability (always-on desktop / foreground pocket) is a
//! deployment mode, not different roles in code. Every client operation is a fresh TCP+TLS
//! connection (MuqClient).

use std::net::SocketAddr;
use std::sync::{Arc, Mutex};

use tokio::net::TcpListener;
use tokio_rustls::TlsAcceptor;

use mt_crypto::{MlkemPublicKey, SecretKey};
use mt_overlay::muq::{ProxyForward, Queue, QueueId, QueueResp};
use mt_overlay::OverlayAddr;

use crate::client::ClientError;
use crate::config::tls_acceptor;
use crate::muq::MuqState;
use crate::muq_client::MuqClient;
use crate::server::{handle_connection, Registry, ServerError};

#[derive(Clone)]
pub struct Node {
    listener: Arc<TcpListener>,
    acceptor: TlsAcceptor,
    reg: Arc<Mutex<Registry>>,
    muq: Arc<MuqState>,
}

impl Node {
    /// Start the node: one TCP listener -- both listens (server) and dials (client methods).
    pub async fn bind(addr: SocketAddr) -> Result<Self, ServerError> {
        let listener = TcpListener::bind(addr).await?;
        Ok(Self {
            listener: Arc::new(listener),
            acceptor: tls_acceptor()?,
            reg: Arc::new(Mutex::new(Registry::default())),
            muq: Arc::new(MuqState::new()),
        })
    }

    pub fn local_addr(&self) -> Result<SocketAddr, ServerError> {
        Ok(self.listener.local_addr()?)
    }

    /// MUQ state of the node (queue-host + courier/proxy routes).
    pub fn muq(&self) -> &Arc<MuqState> {
        &self.muq
    }

    /// Courier role: map an overlay queue-host to its physical address (relay route).
    pub fn add_courier_route(&self, host_overlay: OverlayAddr, addr: SocketAddr) {
        self.muq.add_proxy_route(host_overlay, addr);
    }

    /// Indistinguishable door: accept incoming TCP+TLS connections (host + courier + relay).
    pub async fn run(&self) {
        loop {
            let (tcp, _peer) = match self.listener.accept().await {
                Ok(x) => x,
                Err(_) => continue,
            };
            tcp.set_nodelay(true).ok();
            let acceptor = self.acceptor.clone();
            let reg = self.reg.clone();
            let muq = self.muq.clone();
            tokio::spawn(async move {
                let Ok(tls) = acceptor.accept(tcp).await else {
                    return;
                };
                let _ = handle_connection(tls, reg, muq).await;
            });
        }
    }

    // --- own activity (client role of the single entity): a fresh TCP+TLS per operation ---

    /// Register own queue on the host node.
    pub async fn register_queue_on(
        &self,
        host: SocketAddr,
        q: &Queue,
    ) -> Result<bool, ClientError> {
        // DEV-051 / §534: direct registration only to own node (self-host = loopback).
        // On a foreign host the network identity is exposed -> register_via_courier.
        if !host.ip().is_loopback() {
            return Err(ClientError::ForeignHostRegistration);
        }
        MuqClient::connect(host).await?.register_queue(q).await
    }

    /// Relay registration of a queue on a foreign host via a courier (the host sees the courier, not us).
    pub async fn register_via_courier(
        &self,
        courier: SocketAddr,
        host_overlay: OverlayAddr,
        host_kem_pk: &MlkemPublicKey,
        q: &Queue,
    ) -> Result<bool, ClientError> {
        MuqClient::connect(courier)
            .await?
            .register_via_courier(host_overlay, host_kem_pk, q)
            .await
    }

    /// Place a deposit via a courier node (two-hop; the courier does not see recv_id).
    pub async fn deposit_via(
        &self,
        courier: SocketAddr,
        pf: &ProxyForward,
    ) -> Result<bool, ClientError> {
        MuqClient::connect(courier)
            .await?
            .deposit_via_proxy(pf)
            .await
    }

    /// Two-hop FETCH: collect own shards VIA a courier node (the host sees the courier, not us).
    pub async fn subscribe_via_courier(
        &self,
        courier: SocketAddr,
        host_overlay: OverlayAddr,
        host_kem_pk: &MlkemPublicKey,
        recv_id: QueueId,
        recv_sk: &SecretKey,
    ) -> Result<QueueResp, ClientError> {
        MuqClient::connect(courier)
            .await?
            .subscribe_via_courier(host_overlay, host_kem_pk, recv_id, recv_sk)
            .await
    }

    /// SELF-HOST (absolute against collusion): fetch from OWN queue locally, without a courier
    /// and without the network. No couriers -> nobody to collude -> NOBODY sees the recipient.
    pub fn subscribe_local(&self, recv_id: &QueueId) -> QueueResp {
        QueueResp {
            items: self.muq.local_drain(recv_id),
        }
    }

    /// Public ML-KEM key of the host -- for sealing to this node.
    pub fn host_kem_pubkey(&self) -> MlkemPublicKey {
        self.muq.host_kem_pubkey()
    }
}
