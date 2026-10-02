// 3-peer e2e тест cross-machine networking (M8) — local TCP loopback.
//
// Сетап: 3 montana-node Identity на одной машине через 127.0.0.1 + tcp/0
// (operator-выбираемые порты). Каждый узел знает PeerId двух других через
// тестовый GenesisManifest. Тест запускает 3 Swarm-а параллельно, дожидается
// что все 3 establish connections (2 peers на узел), затем верифицирует
// Ping → Pong handshake между всеми pairs.
//
// Это spec ROADMAP M8 Phase A initial coverage:
//   «cross-machine peering: 3 узла обмениваются ProtocolMessage envelope»
// Проверяется в-process loopback (не реальный cross-machine) — Phase B
// верификация на 3 серверах (мос/фра/зел) — отдельная деплой-фаза.

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

/// Создаёт 3 Identity из детерминированных entropy для воспроизводимости.
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

/// Поднимает swarm-listener на 127.0.0.1:0 (random port), возвращает actual
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

// Test gated на закрытие DEV-012 (multi-node apply_proposal pipeline) и
// полное wire-level пропускание online_session_nonce через IBT handshake
// в swarm builder — оба пути deferred к M9 Phase 2 (см. docs/SPEC_DEVIATIONS.md).
// До закрытия DEV-012 e2e mesh не устанавливает connections в singleton-only
// Active phase guard. Прогон вручную: `cargo test -p montana-node --
// --ignored three_peers`.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "pending DEV-012 multi-node apply_proposal closure"]
async fn three_peers_establish_full_mesh_and_ping_pong() {
    let identities = three_identities();

    // Шаг 1: построить 3 listener-а параллельно через join.
    let (mut s0, addr0) = build_listening_swarm(&identities[0]).await;
    let (mut s1, addr1) = build_listening_swarm(&identities[1]).await;
    let (mut s2, addr2) = build_listening_swarm(&identities[2]).await;

    let pid0 = mt_net_transport::derive_peer_id(&identities[0].node_pk).unwrap();
    let pid1 = mt_net_transport::derive_peer_id(&identities[1].node_pk).unwrap();
    let pid2 = mt_net_transport::derive_peer_id(&identities[2].node_pk).unwrap();

    // Шаг 2: построить mock GenesisManifest с тройкой
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

    // Шаг 3: Каждый узел dial-ит двух других.
    s0.dial(addr1.clone()).expect("s0 → s1 dial");
    s0.dial(addr2.clone()).expect("s0 → s2 dial");
    s1.dial(addr0.clone()).expect("s1 → s0 dial");
    s1.dial(addr2.clone()).expect("s1 → s2 dial");
    s2.dial(addr0.clone()).expect("s2 → s0 dial");
    s2.dial(addr1.clone()).expect("s2 → s1 dial");

    // Шаг 4: poll все 3 swarm-а параллельно. Ждём что каждый узел увидит
    // ConnectionEstablished от двух peer-ов. Затем отправляем Ping и ждём
    // Pong.
    let mut connections_seen: HashSet<(usize, PeerId)> = HashSet::new();
    let mut pong_received: HashSet<usize> = HashSet::new();
    let mut ping_sent_from: HashSet<usize> = HashSet::new();
    let timeout = tokio::time::sleep(Duration::from_secs(20));
    tokio::pin!(timeout);

    loop {
        // Завершение: каждый из 3 узлов получил Pong от хотя бы 1 peer-а.
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

    // Финальные инварианты
    assert_eq!(pong_received.len(), 3, "все 3 узла должны получить Pong");
    assert!(
        connections_seen.len() >= 6,
        "ожидалось ≥6 connection-pair, увидели {}",
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
            // Каждый узел при первом ConnectionEstablished шлёт Ping одному peer-у.
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
