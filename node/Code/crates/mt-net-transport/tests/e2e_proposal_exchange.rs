// Manual Validation Gate scenario 7: proposal exchange e2e test through
// production Noise_PQ XX transport stack.
//
// Spec ROADMAP «Критерий закрытия M6: 2 узла на разных machines обмениваются
// proposals через network». PeerId derivation: SHA-256 multihash of ML-DSA-65
// identity pk; XX upgrade authenticates remote identity inside the handshake.

use std::time::Duration;

use futures::StreamExt;
use libp2p::{
    request_response::{Event as RrEvent, Message as RrMessage},
    swarm::SwarmEvent,
    Multiaddr,
};
use mt_crypto::{keypair_from_seed, KEYPAIR_SEED_SIZE};
use mt_net::{MsgType, ProtocolMessage};
use mt_net_transport::{
    build_swarm, derive_peer_id, MontanaBehaviour, MontanaBehaviourEvent, NetworkConfig,
};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn proposal_envelope_round_trip() {
    let listen: Multiaddr = "/ip4/127.0.0.1/tcp/0".parse().unwrap();
    let cfg = NetworkConfig {
        listen_addrs: vec![listen.clone()],
        max_inbound: 13,
        max_outbound: 24,
    };

    let (s_pk, s_sk) = keypair_from_seed(&[0x70u8; KEYPAIR_SEED_SIZE]).unwrap();
    let (c_pk, c_sk) = keypair_from_seed(&[0x71u8; KEYPAIR_SEED_SIZE]).unwrap();
    let server_xx_peer_id = derive_peer_id(&s_pk).unwrap();

    let mut server = build_swarm(MontanaBehaviour::new(), &cfg, s_pk, s_sk).expect("server swarm");
    let mut client = build_swarm(
        MontanaBehaviour::new(),
        &NetworkConfig {
            listen_addrs: vec![],
            max_inbound: 13,
            max_outbound: 24,
        },
        c_pk,
        c_sk,
    )
    .expect("client swarm");

    let server_addr = loop {
        if let SwarmEvent::NewListenAddr { address, .. } = server.select_next_some().await {
            break address;
        }
    };
    let server_dial: Multiaddr = format!("{server_addr}/p2p/{server_xx_peer_id}")
        .parse()
        .unwrap();
    client.dial(server_dial).expect("client dial");

    let synthetic_proposal_payload: Vec<u8> = (0..512).map(|i| (i & 0xFF) as u8).collect();
    let proposal_request = ProtocolMessage::new(
        MsgType::Proposal,
        0x1234_5678_9ABC_DEF0,
        synthetic_proposal_payload.clone(),
    );
    let ack_response = ProtocolMessage::new(MsgType::Pong, 0x1234_5678_9ABC_DEF0, vec![]);

    let mut req_id = None;
    let timeout = tokio::time::sleep(Duration::from_secs(30));
    tokio::pin!(timeout);

    loop {
        tokio::select! {
            _ = &mut timeout => panic!("e2e timeout"),
            ev = server.select_next_some() => {
                if let SwarmEvent::Behaviour(MontanaBehaviourEvent::RequestResponse(
                    RrEvent::Message {
                        message: RrMessage::Request { request: req, channel, .. },
                        ..
                    },
                )) = ev
                {
                    assert_eq!(req.msg_type, MsgType::Proposal);
                    assert_eq!(req.payload.len(), 512);
                    assert_eq!(req.payload, synthetic_proposal_payload);
                    server.behaviour_mut().request_response.send_response(channel, ack_response.clone()).expect("send response");
                }
            }
            ev = client.select_next_some() => {
                match ev {
                    SwarmEvent::ConnectionEstablished { peer_id, .. } => {
                        let id = client.behaviour_mut().request_response.send_request(&peer_id, proposal_request.clone());
                        req_id = Some(id);
                    }
                    SwarmEvent::Behaviour(MontanaBehaviourEvent::RequestResponse(
                        RrEvent::Message {
                            message: RrMessage::Response { request_id: rid, response },
                            ..
                        },
                    )) => {
                        assert_eq!(Some(rid), req_id);
                        assert_eq!(response, ack_response);
                        return;
                    }
                    _ => {}
                }
            }
        }
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn large_payload_near_max_limit() {
    let listen: Multiaddr = "/ip4/127.0.0.1/tcp/0".parse().unwrap();

    let (s_pk, s_sk) = keypair_from_seed(&[0x80u8; KEYPAIR_SEED_SIZE]).unwrap();
    let (c_pk, c_sk) = keypair_from_seed(&[0x81u8; KEYPAIR_SEED_SIZE]).unwrap();
    let server_xx_peer_id = derive_peer_id(&s_pk).unwrap();

    let mut server = build_swarm(
        MontanaBehaviour::new(),
        &NetworkConfig {
            listen_addrs: vec![listen],
            max_inbound: 13,
            max_outbound: 24,
        },
        s_pk,
        s_sk,
    )
    .expect("server swarm");
    let mut client = build_swarm(
        MontanaBehaviour::new(),
        &NetworkConfig {
            listen_addrs: vec![],
            max_inbound: 13,
            max_outbound: 24,
        },
        c_pk,
        c_sk,
    )
    .expect("client swarm");

    let server_addr = loop {
        if let SwarmEvent::NewListenAddr { address, .. } = server.select_next_some().await {
            break address;
        }
    };
    let dial: Multiaddr = format!("{server_addr}/p2p/{server_xx_peer_id}")
        .parse()
        .unwrap();
    client.dial(dial).unwrap();

    let big = vec![0xCD; 512 * 1024];
    let req = ProtocolMessage::new(MsgType::FastSyncResponse, 1, big.clone());
    let resp = ProtocolMessage::new(MsgType::Pong, 1, vec![]);
    let mut id = None;
    let timeout = tokio::time::sleep(Duration::from_secs(30));
    tokio::pin!(timeout);
    loop {
        tokio::select! {
            _ = &mut timeout => panic!("timeout"),
            ev = server.select_next_some() => {
                if let SwarmEvent::Behaviour(MontanaBehaviourEvent::RequestResponse(
                    RrEvent::Message { message: RrMessage::Request { request, channel, .. }, .. }
                )) = ev {
                    assert_eq!(request.payload.len(), 512 * 1024);
                    server.behaviour_mut().request_response.send_response(channel, resp.clone()).unwrap();
                }
            }
            ev = client.select_next_some() => {
                match ev {
                    SwarmEvent::ConnectionEstablished { peer_id, .. } => {
                        id = Some(client.behaviour_mut().request_response.send_request(&peer_id, req.clone()));
                    }
                    SwarmEvent::Behaviour(MontanaBehaviourEvent::RequestResponse(
                        RrEvent::Message { message: RrMessage::Response { request_id: r, response }, .. }
                    )) => {
                        assert_eq!(Some(r), id);
                        assert_eq!(response, resp);
                        return;
                    }
                    _ => {}
                }
            }
        }
    }
}
