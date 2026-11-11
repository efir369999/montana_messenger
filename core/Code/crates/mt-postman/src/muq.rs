//! MUQ layer of the postman (Montana P2P Network, Stage 2): unlinkable store-and-forward
//! delivery over TCP+TLS (spec §152, TCP/TLS-443 is mandatory). Node roles: queue-host
//! (holds the queues + the shard buffer) and entry-proxy (two hops: accepts ProxyForward from
//! the sender, unwraps the transport, forwards the sealed HostDeposit to the host). The MUQ client
//! connects WITHOUT the Stage 1 overlay registration (the host sees an ephemeral queue key, NOT
//! the account_id, which gives unlinkability). The byte-exact core is mt_overlay::{muq, queue_host}; only
//! the TCP+TLS transport lives here. Each operation = one short connection (one duplex
//! stream: the side reads the request, then writes the response on the same `&mut S`).

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};

use rustls::pki_types::ServerName;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpStream;
use tokio_rustls::client::TlsStream;

use mt_crypto::{
    keypair_from_seed_mlkem, open_from, MlkemPublicKey, MlkemSecretKey, Signature, MLKEM_SEED_SIZE,
};
use mt_overlay::muq::{
    HostDeposit, ProxyForward, Queue, QueueId, QueueItem, QueueResp, QueueSubscribe, ReceiveProxy,
    QUEUE_WIRE_SIZE,
};
use mt_overlay::queue_host::QueueHost;
use mt_overlay::OverlayAddr;

use crate::config::{tls_connector, STAND_SNI};
use crate::wire::{read_fixed, recv_frame, send_frame, write_fixed, WireError};

/// Tags of MUQ operations (first byte of the connection). REG_VERSION=0x01 is the Stage 1 path.
pub(crate) fn ack_ok() -> u8 {
    OK
}

pub const TAG_QUEUE_REGISTER: u8 = 0x10;
pub const TAG_HOST_DEPOSIT: u8 = 0x11;
pub const TAG_PROXY_FORWARD: u8 = 0x12;
pub const TAG_RECEIVE_PROXY: u8 = 0x14; // B -> courier (two-hop fetch)
pub const TAG_RELAY_SUBSCRIBE: u8 = 0x15; // courier → host
pub const TAG_PROXY_REGISTER: u8 = 0x16; // B -> courier (relay registration)
pub const TAG_RELAY_REGISTER: u8 = 0x17; // courier → host
pub const TAG_RECEIVE_NONCE: u8 = 0x18; // B -> courier: request a host-issued nonce (§478)
pub const TAG_RELAY_NONCE: u8 = 0x19; // courier -> host: forward sealed recv_id, return the nonce
pub const TAG_RECEIVE_ACK: u8 = 0x1A; // B -> courier: receipt acknowledgment (§593)
pub const TAG_RELAY_ACK: u8 = 0x1B; // courier → host: forward sealed recv_id, drop buffer
pub const TAG_NODE_HELLO: u8 = 0x1C; // sender → node: get capability (host_kem + send_id)

const OK: u8 = 0x01;
const ERR: u8 = 0x00;

/// State of a MUQ node: host queue table + proxy routes (overlay host -> physical address of the stand).
// V-1: locks recover from poison (unwrap_or_else into_inner): a panic of one
// handler does not poison the whole postman node that serves many.
pub struct MuqState {
    host: Mutex<QueueHost>,
    proxy_routes: Mutex<HashMap<OverlayAddr, SocketAddr>>,
    /// ML-KEM keypair of the host: the client seals to host_kem_pk, only the host can open it.
    /// The courier is crypto-blind to the sealed content (recv_id/deposit), so anonymity holds.
    host_kem_pk: MlkemPublicKey,
    host_kem_sk: MlkemSecretKey,
}

impl Default for MuqState {
    fn default() -> Self {
        let mut seed = [0u8; MLKEM_SEED_SIZE];
        getrandom::getrandom(&mut seed).expect("OS CSPRNG");
        let (host_kem_pk, host_kem_sk) = keypair_from_seed_mlkem(&seed).expect("ML-KEM keygen");
        Self {
            host: Mutex::new(QueueHost::new()),
            proxy_routes: Mutex::new(HashMap::new()),
            host_kem_pk,
            host_kem_sk,
        }
    }
}

impl MuqState {
    /// DEV-049(d): eviction of expired shards by TTL (called by the node prune timer).
    pub(crate) fn prune_expired(&self, window: u64) {
        self.host
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .prune(window);
    }

    pub fn new() -> Self {
        Self::default()
    }

    /// Backend postman: deterministic ML-KEM identity from a persisted seed, so clients know a
    /// stable host_kem_pk across restarts. The seed is kept by the operator (postman-identity.bin).
    pub fn from_seed(seed: &[u8; MLKEM_SEED_SIZE]) -> Self {
        let (host_kem_pk, host_kem_sk) =
            keypair_from_seed_mlkem(seed).expect("ML-KEM keygen from seed");
        Self {
            host: Mutex::new(QueueHost::new()),
            proxy_routes: Mutex::new(HashMap::new()),
            host_kem_pk,
            host_kem_sk,
        }
    }

    /// Proxy role: map the overlay address of a queue-host to its physical address.
    pub fn add_proxy_route(&self, host_overlay: OverlayAddr, addr: SocketAddr) {
        self.proxy_routes
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .insert(host_overlay, addr);
    }

    /// send_id of the registered queue (self-host: one), for the hello exchange.
    pub fn primary_send_id(&self) -> Option<QueueId> {
        self.host
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .any_send_id()
    }

    /// Public ML-KEM key of the host: the client seals to it (the courier is crypto-blind).
    pub fn host_kem_pubkey(&self) -> MlkemPublicKey {
        MlkemPublicKey::from_array(*self.host_kem_pk.as_bytes())
    }

    /// Local drain of own queue (self-host, WITHOUT a courier): the absolute guard against collusion.
    pub fn local_drain(&self, recv_id: &QueueId) -> Vec<QueueItem> {
        let mut host = self.host.lock().unwrap_or_else(|p| p.into_inner());
        let items = host.buffer_of(recv_id);
        for it in &items {
            host.drop_delivered(recv_id, &it.msg_id);
        }
        items
    }

    /// Number of shards in the queue buffer (observability/tests).
    pub fn buffer_len(&self, recv_id: &QueueId) -> usize {
        self.host
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .buffer_of(recv_id)
            .len()
    }
}

/// Handling of one MUQ operation on a fresh TCP+TLS connection (tag already read by the server).
/// Each client operation = a separate connection (unlinkable: the node sees only an ephemeral queue key), so there is no loop.
pub async fn handle_muq_op<S: AsyncRead + AsyncWrite + Unpin>(
    tag: u8,
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    dispatch(tag, st, state).await
}

async fn dispatch<S: AsyncRead + AsyncWrite + Unpin>(
    tag: u8,
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    match tag {
        TAG_QUEUE_REGISTER => handle_register(st, state).await,
        TAG_HOST_DEPOSIT => handle_deposit(st, state).await,
        TAG_PROXY_FORWARD => handle_proxy_forward(st, state).await,
        TAG_RECEIVE_PROXY => handle_receive_proxy(st, state).await,
        TAG_RELAY_SUBSCRIBE => handle_relay_subscribe(st, state).await,
        TAG_PROXY_REGISTER => handle_proxy_register(st, state).await,
        TAG_RELAY_REGISTER => handle_relay_register(st, state).await,
        TAG_RECEIVE_NONCE => handle_receive_nonce(st, state).await,
        TAG_RELAY_NONCE => handle_relay_nonce(st, state).await,
        TAG_RECEIVE_ACK => handle_receive_ack(st, state).await,
        TAG_RELAY_ACK => handle_relay_ack(st, state).await,
        TAG_NODE_HELLO => handle_node_hello(st, state).await,
        _ => Ok(()),
    }
}

/// The recipient registers a queue on the host (recv_id/send_id are independent, recv_pubkey is ephemeral).
async fn handle_register<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let mut buf = [0u8; QUEUE_WIRE_SIZE];
    read_fixed(st, &mut buf).await?;
    let ack = match Queue::decode(&buf) {
        Ok(q) => {
            let accepted = state
                .host
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .register_queue(q, current_window());
            if accepted {
                OK
            } else {
                ERR
            }
        },
        Err(_) => ERR,
    };
    write_fixed(st, &[ack]).await?;
    Ok(())
}

/// DEV-049(d): current window from the system clock (floor(unix/60)) for shard storage TTL.
/// Off-chain ([P2P-1]): MUQ transport is NOT part of the consensus root, so the system clock is allowed
/// for TTL eviction (not for consensus values; those use TimeChain only).
pub(crate) fn current_window() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() / 60)
        .unwrap_or(0)
}

async fn handle_deposit<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let sealed = recv_frame(st).await?;
    let ack = match open_from(&state.host_kem_sk, &sealed)
        .ok()
        .and_then(|b| HostDeposit::decode(&b).ok())
    {
        Some(hd) => {
            let w = current_window();
            match state
                .host
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .deposit(&hd, w)
            {
                Ok(()) => OK,
                Err(_) => ERR,
            }
        },
        None => ERR,
    };
    write_fixed(st, &[ack]).await?;
    Ok(())
}

/// Entry-proxy: unwraps the transport, forwards the sealed HostDeposit to the host (the proxy does not see recv_id).
async fn handle_proxy_forward<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let bytes = recv_frame(st).await?;
    let ack = match ProxyForward::decode(&bytes) {
        Ok(pf) => match route_of(state, &pf.host_addr) {
            Some(addr) => match forward_deposit_to_host(addr, &pf.sealed).await {
                Ok(()) => OK,
                Err(_) => ERR,
            },
            None => ERR,
        },
        Err(_) => ERR,
    };
    write_fixed(st, &[ack]).await?;
    Ok(())
}

/// Courier: accepts ReceiveProxy from the recipient, carries the sealed QueueSubscribe to the host
/// (two-hop fetch), returns QueueResp back. The courier does NOT see recv_id (sealed is opaque).
async fn handle_receive_proxy<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let bytes = recv_frame(st).await?;
    // DEV-052: do NOT map errors to an empty QueueResp, otherwise B cannot tell "no mail" from
    // "delivery broke". A forward error propagates, B sees the error and refetches.
    let rp = ReceiveProxy::decode(&bytes).map_err(|_| WireError::Closed)?;
    let Some(addr) = route_of(state, &rp.host_addr) else {
        return Err(WireError::Closed); // no route: an explicit error, not a silent empty
    };
    let resp = forward_subscribe_to_host(addr, &rp.sealed).await?; // forward-fail → propagate
    send_frame(st, &resp).await?;
    Ok(())
}

/// DEV-050(c) §478: the courier forwards the nonce request to the host and returns the 16-byte
/// host-issued nonce to the recipient. The courier is crypto-blind (sealed recv_id).
async fn handle_receive_nonce<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let bytes = recv_frame(st).await?;
    let pf = ProxyForward::decode(&bytes).map_err(|_| WireError::Closed)?;
    let Some(addr) = route_of(state, &pf.host_addr) else {
        return Err(WireError::Closed);
    };
    let nonce = forward_nonce_to_host(addr, &pf.sealed).await?;
    write_fixed(st, &nonce).await?;
    Ok(())
}

/// DEV-050(c): the host opens the sealed recv_id and issues a fresh one-time nonce (issue_nonce).
async fn handle_relay_nonce<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let sealed = recv_frame(st).await?;
    let nonce = match open_from(&state.host_kem_sk, &sealed) {
        Ok(b) if b.len() == 32 => {
            let mut rid = [0u8; 32];
            rid.copy_from_slice(&b);
            state
                .host
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .issue_nonce(&rid)
        },
        _ => [0u8; 16], // error: zero nonce (subscribe rejects it: not issued)
    };
    write_fixed(st, &nonce).await?;
    Ok(())
}

/// DEV-049(a) §593: the courier forwards the receipt acknowledgment to the host (drop-on-ack).
async fn handle_receive_ack<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let bytes = recv_frame(st).await?;
    let pf = ProxyForward::decode(&bytes).map_err(|_| WireError::Closed)?;
    let Some(addr) = route_of(state, &pf.host_addr) else {
        return Err(WireError::Closed);
    };
    let ok = forward_ack_to_host(addr, &pf.sealed).await?;
    write_fixed(st, &[ok]).await?;
    Ok(())
}

/// Host: receipt acknowledgment; opens the sealed recv_id and drops the queue buffer.
async fn handle_relay_ack<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let sealed = recv_frame(st).await?;
    let ack = match open_from(&state.host_kem_sk, &sealed)
        .ok()
        .and_then(|b| QueueSubscribe::decode(&b).ok())
    {
        Some(sub) => {
            let sig = Signature::from_array(sub.sig);
            let ok = state
                .host
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .ack_drain(&sub.recv_id, &sub.nonce, &sig);
            if ok {
                OK
            } else {
                ERR
            }
        },
        None => ERR,
    };
    write_fixed(st, &[ack]).await?;
    Ok(())
}

/// Host: relay fetch from the courier. verify_subscribe + nonce-tracking (anti-replay), returns
/// QueueResp to the courier. The host sees the courier, NOT the network identity of recipient B.
async fn handle_relay_subscribe<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let sealed = recv_frame(st).await?;
    let sub = match open_from(&state.host_kem_sk, &sealed)
        .ok()
        .and_then(|b| QueueSubscribe::decode(&b).ok())
    {
        Some(s) => s,
        None => {
            let _ = send_frame(st, &QueueResp { items: vec![] }.to_bytes()).await;
            return Ok(());
        },
    };
    let sig = Signature::from_array(sub.sig);
    let items: Vec<QueueItem> = {
        let mut host = state.host.lock().unwrap_or_else(|p| p.into_inner());
        host.subscribe_relay(&sub.recv_id, &sub.nonce, &sig)
            .unwrap_or_default()
    };
    let resp = QueueResp { items };
    send_frame(st, &resp.to_bytes()).await?;
    // DEV-049(a) §593: do NOT drop here; the buffer is held until the E2E acknowledgment from B
    // (mt_client_ack, then ack_drain). Transit survives failure of the courier-to-B leg.
    Ok(())
}

/// Courier: relay registration; carries the sealed Queue to the host (the courier does not see recv_id).
async fn handle_proxy_register<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let bytes = recv_frame(st).await?;
    let ack = match ProxyForward::decode(&bytes) {
        Ok(pf) => match route_of(state, &pf.host_addr) {
            Some(addr) => match forward_register_to_host(addr, &pf.sealed).await {
                Ok(()) => OK,
                Err(_) => ERR,
            },
            None => ERR,
        },
        Err(_) => ERR,
    };
    write_fixed(st, &[ack]).await?;
    Ok(())
}

/// Host: relay registration from the courier; unwraps the Queue (ML-KEM) and registers it.
async fn handle_relay_register<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let sealed = recv_frame(st).await?;
    let ack = match open_from(&state.host_kem_sk, &sealed)
        .ok()
        .and_then(|b| Queue::decode(&b).ok())
    {
        Some(q) => {
            let accepted = state
                .host
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .register_queue(q, current_window());
            if accepted {
                OK
            } else {
                ERR
            }
        },
        None => ERR,
    };
    write_fixed(st, &[ack]).await?;
    Ok(())
}

/// Node hello: hand out the node capability: host_kem (1184) + send_id (32) of its queue.
/// The sender finds the node via mDNS, connects, gets hello, and deposits without a map.
async fn handle_node_hello<S: AsyncRead + AsyncWrite + Unpin>(
    st: &mut S,
    state: &Arc<MuqState>,
) -> Result<(), WireError> {
    let kem = state.host_kem_pubkey();
    let sid = state.primary_send_id().unwrap_or([0u8; 32]);
    write_fixed(st, kem.as_bytes()).await?;
    write_fixed(st, &sid).await?;
    Ok(())
}

// --- Courier-to-host forwarding: a fresh TCP+TLS connection for every forward ---

fn route_of(state: &Arc<MuqState>, host: &OverlayAddr) -> Option<SocketAddr> {
    state
        .proxy_routes
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .get(host)
        .copied()
}

/// Open a fresh TCP+TLS stream from the courier to the physical address of the host.
async fn open_to_host(host_addr: SocketAddr) -> Result<TlsStream<TcpStream>, WireError> {
    let tcp = TcpStream::connect(host_addr)
        .await
        .map_err(|_| WireError::Closed)?;
    tcp.set_nodelay(true).ok();
    let connector = tls_connector().map_err(|_| WireError::Closed)?;
    let sni = ServerName::try_from(STAND_SNI)
        .map_err(|_| WireError::Closed)?
        .to_owned();
    connector
        .connect(sni, tcp)
        .await
        .map_err(|_| WireError::Closed)
}

/// The proxy opens a connection to the host and sends the sealed payload as HostDeposit.
async fn forward_deposit_to_host(host_addr: SocketAddr, sealed: &[u8]) -> Result<(), WireError> {
    let mut st = open_to_host(host_addr).await?;
    write_fixed(&mut st, &[TAG_HOST_DEPOSIT]).await?;
    send_frame(&mut st, sealed).await?;
    let mut ack = [0u8; 1];
    let _ = read_fixed(&mut st, &mut ack).await; // wait for the ack (guarantee of deposit delivery)
    Ok(())
}

async fn forward_subscribe_to_host(
    host_addr: SocketAddr,
    sealed: &[u8],
) -> Result<Vec<u8>, WireError> {
    let mut st = open_to_host(host_addr).await?;
    write_fixed(&mut st, &[TAG_RELAY_SUBSCRIBE]).await?;
    send_frame(&mut st, sealed).await?;
    recv_frame(&mut st).await
}

async fn forward_nonce_to_host(
    host_addr: SocketAddr,
    sealed: &[u8],
) -> Result<[u8; 16], WireError> {
    let mut st = open_to_host(host_addr).await?;
    write_fixed(&mut st, &[TAG_RELAY_NONCE]).await?;
    send_frame(&mut st, sealed).await?;
    let mut nonce = [0u8; 16];
    read_fixed(&mut st, &mut nonce).await?;
    Ok(nonce)
}

async fn forward_ack_to_host(host_addr: SocketAddr, sealed: &[u8]) -> Result<u8, WireError> {
    let mut st = open_to_host(host_addr).await?;
    write_fixed(&mut st, &[TAG_RELAY_ACK]).await?;
    send_frame(&mut st, sealed).await?;
    let mut ack = [0u8; 1];
    read_fixed(&mut st, &mut ack).await?;
    Ok(ack[0])
}

async fn forward_register_to_host(host_addr: SocketAddr, sealed: &[u8]) -> Result<(), WireError> {
    let mut st = open_to_host(host_addr).await?;
    write_fixed(&mut st, &[TAG_RELAY_REGISTER]).await?;
    send_frame(&mut st, sealed).await?;
    let mut ack = [0u8; 1];
    let _ = read_fixed(&mut st, &mut ack).await;
    Ok(())
}
