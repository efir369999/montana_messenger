// spec, раздел "Сетевой уровень → Cross-machine peering" (M8) — Noise_PQ XX
// is the production transport. PeerId is derived from each peer's ML-DSA-65
// identity public key via SHA-256 multihash (sha2-256 multihash code 0x12).
//
// Spec connection lifecycle:
//   TCP → Noise_PQ XX handshake (ML-KEM-768 + ML-DSA-65) → Yamux multiplex
//
// The libp2p Ed25519 keypair is still required by SwarmBuilder for its
// internal book-keeping, but the cross-network identity is the ML-DSA-65 pk —
// not the Ed25519 pk. Each node's GenesisManifest peer_id MUST be the
// ML-DSA-derived multihash to align with what the XX upgrade returns.

use std::collections::HashMap;
use std::str::FromStr;
use std::time::Duration;

use futures::StreamExt;
use libp2p::request_response::{Event as RrEvent, Message as RrMessage};
use libp2p::swarm::SwarmEvent;
use libp2p::{Multiaddr, PeerId, Swarm};
use mt_crypto::{PublicKey as MtPublicKey, SecretKey as MtSecretKey};
use mt_genesis::GenesisManifest;
use mt_net::{MsgType, ProtocolMessage};
use mt_net_transport::{
    build_swarm_with_keypair, MontanaBehaviour, MontanaBehaviourEvent, NetworkConfig,
};

use crate::identity::NodeError;

const HEARTBEAT_PERIOD: Duration = Duration::from_secs(5);

#[allow(clippy::too_many_arguments)]
pub async fn run_network_loop(
    local_keypair: libp2p::identity::Keypair,
    local_peer_id: PeerId,
    mldsa_id_pk: MtPublicKey,
    mldsa_id_sk: MtSecretKey,
    manifest: GenesisManifest,
    listen_addr: Multiaddr,
    mut broadcast_rx: tokio::sync::mpsc::UnboundedReceiver<ProtocolMessage>,
    incoming_tx: tokio::sync::mpsc::UnboundedSender<ProtocolMessage>,
) -> Result<(), NodeError> {
    let cfg = NetworkConfig {
        listen_addrs: vec![listen_addr.clone()],
        max_inbound: 13,
        max_outbound: 24,
    };

    let mut swarm: Swarm<MontanaBehaviour> = build_swarm_with_keypair(
        local_keypair,
        MontanaBehaviour::new(),
        &cfg,
        mldsa_id_pk,
        mldsa_id_sk,
    )
    .map_err(|e| NodeError::Network(format!("build swarm: {e}")))?;

    eprintln!(
        "[network] local_peer_id={local_peer_id} listen={listen_addr} \
         peers_to_dial={cnt}",
        cnt = manifest.peers.len() - 1
    );

    let mut dialed: HashMap<PeerId, String> = HashMap::new();
    // Цели перенабора: соседи из манифеста; при потере соединения (или если
    // сосед ещё не поднялся на старте) набираем заново на каждом ударе
    // сердцебиения — сеть обязана сцепляться «из коробки», без рестартов.
    let mut redial_targets: Vec<(PeerId, String, Multiaddr)> = Vec::new();
    for peer in &manifest.peers {
        let peer_id_parsed = PeerId::from_str(&peer.peer_id)
            .map_err(|e| NodeError::Network(format!("invalid peer_id {}: {e}", peer.peer_id)))?;
        if peer_id_parsed == local_peer_id {
            continue;
        }
        let multiaddr_parsed = Multiaddr::from_str(&peer.multiaddr).map_err(|e| {
            NodeError::Network(format!("invalid multiaddr {}: {e}", peer.multiaddr))
        })?;
        let dial_target: Multiaddr = format!("{}/p2p/{}", multiaddr_parsed, peer_id_parsed)
            .parse()
            .map_err(|e: libp2p::multiaddr::Error| {
                NodeError::Network(format!("compose multiaddr: {e}"))
            })?;
        eprintln!("[network] dialing {} ({})", peer.label, dial_target);
        swarm
            .dial(dial_target.clone())
            .map_err(|e| NodeError::Network(format!("dial {}: {e}", peer.label)))?;
        dialed.insert(peer_id_parsed, peer.label.clone());
        redial_targets.push((peer_id_parsed, peer.label.clone(), dial_target));
    }

    let mut heartbeat = tokio::time::interval(HEARTBEAT_PERIOD);
    heartbeat.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let mut request_id_counter: u64 = 0;
    let mut connected_peers: HashMap<PeerId, String> = HashMap::new();

    loop {
        tokio::select! {
            ev = swarm.select_next_some() => {
                match ev {
                    SwarmEvent::NewListenAddr { address, .. } => {
                        eprintln!("[network] listening on {address}/p2p/{local_peer_id}");
                    }
                    SwarmEvent::ConnectionEstablished { peer_id, endpoint, .. } => {
                        let label = dialed
                            .get(&peer_id)
                            .cloned()
                            .unwrap_or_else(|| "unknown".to_string());
                        eprintln!(
                            "[network] CONNECTION ESTABLISHED peer={peer_id} label={label} \
                             remote={remote}",
                            remote = endpoint.get_remote_address()
                        );
                        connected_peers.insert(peer_id, label);
                        request_id_counter = request_id_counter.wrapping_add(1);
                        let initial_ping = ProtocolMessage::new(
                            MsgType::Ping,
                            request_id_counter,
                            Vec::new(),
                        );
                        swarm.behaviour_mut().request_response.send_request(&peer_id, initial_ping);
                    }
                    SwarmEvent::ConnectionClosed { peer_id, cause, .. } => {
                        let label = connected_peers.remove(&peer_id).unwrap_or_default();
                        eprintln!(
                            "[network] connection closed peer={peer_id} label={label} \
                             cause={cause:?}"
                        );
                    }
                    SwarmEvent::OutgoingConnectionError { peer_id, error, .. } => {
                        eprintln!(
                            "[network] outgoing connection ERROR peer={peer_id:?} error={error}"
                        );
                    }
                    SwarmEvent::Behaviour(MontanaBehaviourEvent::RequestResponse(
                        RrEvent::Message {
                            peer: _,
                            message: RrMessage::Request { request, channel, .. },
                            ..
                        },
                    )) => {
                        eprintln!("[network] RR Request msg_type={:?} request_id={} payload_len={}", request.msg_type, request.request_id, request.payload.len());
                        if request.msg_type == MsgType::Ping {
                            let pong = ProtocolMessage::new(MsgType::Pong, request.request_id, Vec::new());
                            if let Err(e) = swarm
                                .behaviour_mut()
                                .request_response
                                .send_response(channel, pong)
                            {
                                eprintln!("[network] send Pong failed: {e:?}");
                            }
                        } else {
                            let msg_type_dbg = request.msg_type;
                            if let Err(e) = incoming_tx.send(request.clone()) {
                                eprintln!("[network] forward {msg_type_dbg:?} failed: {e}");
                            }
                            let ack = ProtocolMessage::new(MsgType::Pong, request.request_id, Vec::new());
                            let _ = swarm.behaviour_mut().request_response.send_response(channel, ack);
                        }
                    }
                    SwarmEvent::Behaviour(MontanaBehaviourEvent::RequestResponse(
                        RrEvent::Message {
                            peer,
                            message: RrMessage::Response { request_id, response },
                            ..
                        },
                    )) if response.msg_type == MsgType::Pong => {
                        eprintln!(
                            "[network] heartbeat OK peer={peer} request_id={request_id}"
                        );
                    }
                    SwarmEvent::Behaviour(MontanaBehaviourEvent::RequestResponse(rr_other)) => {
                        eprintln!("[network] RR other event: {rr_other:?}");
                    }
                    _ => {}
                }
            }
            _ = heartbeat.tick() => {
                for (peer_id, label, addr) in &redial_targets {
                    if !connected_peers.contains_key(peer_id) {
                        eprintln!("[network] redial {} ({})", label, addr);
                        let _ = swarm.dial(addr.clone());
                    }
                }
                let peers: Vec<PeerId> = connected_peers.keys().copied().collect();
                for peer_id in peers {
                    request_id_counter = request_id_counter.wrapping_add(1);
                    let ping = ProtocolMessage::new(
                        MsgType::Ping,
                        request_id_counter,
                        Vec::new(),
                    );
                    swarm.behaviour_mut().request_response.send_request(&peer_id, ping);
                }
            }
            Some(broadcast_msg) = broadcast_rx.recv() => {
                let peers: Vec<PeerId> = connected_peers.keys().copied().collect();
                let msg_type_dbg = broadcast_msg.msg_type;
                let peer_count = peers.len();
                for peer_id in peers {
                    swarm.behaviour_mut().request_response.send_request(&peer_id, broadcast_msg.clone());
                }
                eprintln!(
                    "[network] broadcast {msg_type_dbg:?} request_id={rid} to {peer_count} peer(s)",
                    rid = broadcast_msg.request_id
                );
            }
            _ = tokio::signal::ctrl_c() => {
                eprintln!("[network] Ctrl-C, exiting");
                return Ok(());
            }
        }
    }
}
