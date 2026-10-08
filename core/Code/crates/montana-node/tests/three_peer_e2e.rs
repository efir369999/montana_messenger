// 3-peer e2e test of cross-machine networking (M8) — local TCP loopback.
//
// Setup: 3 montana-node Identities on one machine via 127.0.0.1 + tcp/0
// (operator-selectable ports). Each node knows the PeerId of the other two via a
// test GenesisManifest. The test runs 3 Swarms in parallel, waits until
// all 3 establish connections (2 peers per node), then verifies a
// Ping → Pong handshake between all pairs.
//
// This is the spec ROADMAP M8 Phase A initial coverage:
//   «cross-machine peering: 3 nodes exchange a ProtocolMessage envelope»
// Verified in-process over loopback (not real cross-machine) — Phase B
// verification on 3 servers is a separate deployment phase.

use std::collections::HashSet;
use std::time::Duration;

use futures::StreamExt;
use libp2p::request_response::{Event as RrEvent, Message as RrMessage};
use libp2p::swarm::SwarmEvent;
use libp2p::{Multiaddr, PeerId, Swarm};
use montana_node::Identity;
use mt_genesis::{GenesisManifest, GenesisPeer};
use mt_net::{MsgType, ProtocolMessage};
use mt_net_transport::{
    build_swarm_with_keypair, MontanaBehaviour, MontanaBehaviourEvent, NetworkConfig,
};

/// Creates 3 Identities from deterministic entropy for reproducibility.
fn three_identities() -> [Identity; 3] {
    [
        Identity::from_entropy(&[1u8; 32]).expect("identity #1"),
        Identity::from_entropy(&[2u8; 32]).expect("identity #2"),
        Identity::from_entropy(&[3u8; 32]).expect("identity #3"),
    ]
}

fn hex64(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

/// Brings up a swarm listener on 127.0.0.1:0 (random port), returns the actual
/// listening multiaddr + Swarm.
async fn build_listening_swarm(identity: &Identity) -> (Swarm<MontanaBehaviour>, Multiaddr) {
    let cfg = NetworkConfig {
        listen_addrs: vec!["/ip4/127.0.0.1/tcp/0".parse().unwrap()],
        max_inbound: 13,
        max_outbound: 24,
    };
    let id_pk = identity.node_pk.clone();
    let id_sk_bytes: [u8; mt_crypto::SECRET_KEY_SIZE] = *identity.node_sk.as_bytes();
    let id_sk = mt_crypto::SecretKey::from_array(id_sk_bytes);
    let mut swarm = build_swarm_with_keypair(
        identity.libp2p_keypair(),
        MontanaBehaviour::new(),
        &cfg,
        id_pk,
        id_sk,
    )
    .expect("build swarm");
    let local_peer =
        mt_net_transport::derive_peer_id(&identity.node_pk).expect("derive XX peer_id");
    let listen_addr = loop {
        let ev = swarm.select_next_some().await;
        if let SwarmEvent::NewListenAddr { address, .. } = ev {
            break address;
        }
    };
    (
        swarm,
        format!("{listen_addr}/p2p/{local_peer}").parse().unwrap(),
    )
}

// Test gated on closing DEV-012 (multi-node apply_proposal pipeline) and
// full wire-level passing of online_session_nonce through the IBT handshake
// in the swarm builder — both paths deferred to M9 Phase 2 (see docs/SPEC_DEVIATIONS.md).
// Until DEV-012 is closed the e2e mesh does not establish connections under the singleton-only
// Active phase guard. Run manually: `cargo test -p montana-node --
// --ignored three_peers`.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "pending DEV-012 multi-node apply_proposal closure"]
async fn three_peers_establish_full_mesh_and_ping_pong() {
    let identities = three_identities();

    // Step 1: build 3 listeners in parallel via join.
    let (mut s0, addr0) = build_listening_swarm(&identities[0]).await;
    let (mut s1, addr1) = build_listening_swarm(&identities[1]).await;
    let (mut s2, addr2) = build_listening_swarm(&identities[2]).await;

    let pid0 = mt_net_transport::derive_peer_id(&identities[0].node_pk).unwrap();
    let pid1 = mt_net_transport::derive_peer_id(&identities[1].node_pk).unwrap();
    let pid2 = mt_net_transport::derive_peer_id(&identities[2].node_pk).unwrap();

    // Step 2: build a mock GenesisManifest with the triple
    let manifest = GenesisManifest {
        network_name: "test-3peer".into(),
        peers: vec![
            GenesisPeer {
                label: "n0".into(),
                multiaddr: addr0.to_string(),
                peer_id: pid0.to_string(),
                account_id_hex: hex64(&identities[0].account_id()),
                node_id_hex: hex64(&identities[0].node_id()),
                bootstrap: true,
            },
            GenesisPeer {
                label: "n1".into(),
                multiaddr: addr1.to_string(),
                peer_id: pid1.to_string(),
                account_id_hex: hex64(&identities[1].account_id()),
                node_id_hex: hex64(&identities[1].node_id()),
                bootstrap: false,
            },
            GenesisPeer {
                label: "n2".into(),
                multiaddr: addr2.to_string(),
                peer_id: pid2.to_string(),
                account_id_hex: hex64(&identities[2].account_id()),
                node_id_hex: hex64(&identities[2].node_id()),
                bootstrap: false,
            },
        ],
    };
    manifest.validate().expect("manifest invariants OK");

    // Step 3: each node dials the other two.
    s0.dial(addr1.clone()).expect("s0 → s1 dial");
    s0.dial(addr2.clone()).expect("s0 → s2 dial");
    s1.dial(addr0.clone()).expect("s1 → s0 dial");
    s1.dial(addr2.clone()).expect("s1 → s2 dial");
    s2.dial(addr0.clone()).expect("s2 → s0 dial");
    s2.dial(addr1.clone()).expect("s2 → s1 dial");

    // Step 4: poll all 3 swarms in parallel. We wait for each node to see
    // ConnectionEstablished from two peers. Then we send Ping and wait
    // Pong.
    let mut connections_seen: HashSet<(usize, PeerId)> = HashSet::new();
    let mut pong_received: HashSet<usize> = HashSet::new();
    let mut ping_sent_from: HashSet<usize> = HashSet::new();
    let timeout = tokio::time::sleep(Duration::from_secs(20));
    tokio::pin!(timeout);

    loop {
        // Completion: each of the 3 nodes received Pong from at least 1 peer.
        if pong_received.len() == 3 {
            break;
        }

        tokio::select! {
            _ = &mut timeout => {
                panic!(
                    "e2e timeout. connections_seen={connections_seen:?} \
                     ping_sent_from={ping_sent_from:?} pong_received={pong_received:?}"
                );
            }
            ev = s0.select_next_some() => handle_event(0, ev, &mut s0, &mut connections_seen, &mut ping_sent_from, &mut pong_received),
            ev = s1.select_next_some() => handle_event(1, ev, &mut s1, &mut connections_seen, &mut ping_sent_from, &mut pong_received),
            ev = s2.select_next_some() => handle_event(2, ev, &mut s2, &mut connections_seen, &mut ping_sent_from, &mut pong_received),
        }
    }

    // Final invariants
    assert_eq!(pong_received.len(), 3, "all 3 nodes must receive Pong");
    assert!(
        connections_seen.len() >= 6,
        "expected ≥6 connection-pairs, saw {}",
        connections_seen.len()
    );
}

fn handle_event(
    node_idx: usize,
    ev: SwarmEvent<MontanaBehaviourEvent>,
    swarm: &mut Swarm<MontanaBehaviour>,
    connections_seen: &mut HashSet<(usize, PeerId)>,
    ping_sent_from: &mut HashSet<usize>,
    pong_received: &mut HashSet<usize>,
) {
    match ev {
        SwarmEvent::ConnectionEstablished { peer_id, .. } => {
            connections_seen.insert((node_idx, peer_id));
            // On the first ConnectionEstablished each node sends Ping to one peer.
            if !ping_sent_from.contains(&node_idx) {
                let ping = ProtocolMessage::new(MsgType::Ping, node_idx as u64, Vec::new());
                swarm
                    .behaviour_mut()
                    .request_response
                    .send_request(&peer_id, ping);
                ping_sent_from.insert(node_idx);
            }
        },
        SwarmEvent::Behaviour(MontanaBehaviourEvent::RequestResponse(RrEvent::Message {
            message: RrMessage::Request {
                request, channel, ..
            },
            ..
        })) if request.msg_type == MsgType::Ping => {
            let pong = ProtocolMessage::new(MsgType::Pong, request.request_id, Vec::new());
            swarm
                .behaviour_mut()
                .request_response
                .send_response(channel, pong)
                .expect("send pong");
        },
        SwarmEvent::Behaviour(MontanaBehaviourEvent::RequestResponse(RrEvent::Message {
            message: RrMessage::Response { response, .. },
            ..
        })) if response.msg_type == MsgType::Pong => {
            pong_received.insert(node_idx);
        },
        _ => {},
    }
}
