//! Running test of Stage 2 (MUQ store-and-forward) under the Stage 3 model: the host does NOT see
//! the recipient: registration AND fetch go through a courier (default non-collusion), there are no direct
//! B<->host operations. Offline delivery through two hops + RS(2,3) durability.

use std::time::Duration;

use mt_overlay::erasure::{rs_reconstruct, rs_split};
use mt_overlay::muq::{derive_queue_keypairs, sign_deposit, HostDeposit, ProxyForward, Queue};
use mt_overlay::OverlayAddr;
use mt_postman::{MuqClient, PostmanServer};

async fn with_timeout<F: std::future::Future>(f: F) -> F::Output {
    tokio::time::timeout(Duration::from_secs(10), f)
        .await
        .expect("must not hang for more than 10s")
}

fn make_queue(
    recv_id: [u8; 32],
    send_id: [u8; 32],
) -> (Queue, mt_crypto::SecretKey, mt_crypto::SecretKey) {
    let rs = [0x42u8; 32];
    let ((recv_pk, recv_sk), (send_pk, send_sk)) = derive_queue_keypairs(&rs, 0).unwrap();
    let q = Queue {
        recv_id,
        send_id,
        recv_pubkey: *recv_pk.as_bytes(),
        send_pubkey: Some(*send_pk.as_bytes()),
        rotation_epoch: 1000,
        quota: 64,
    };
    (q, recv_sk, send_sk)
}

#[allow(clippy::too_many_arguments)]
fn build_deposit(
    send_id: [u8; 32],
    send_sk: &mt_crypto::SecretKey,
    msg_id: [u8; 16],
    shard_index: u8,
    shard_total: u8,
    ct: Vec<u8>,
    host_overlay: OverlayAddr,
    host_kem_pk: &mt_crypto::MlkemPublicKey,
) -> ProxyForward {
    let nonce = [0x07u8; 16];
    let sig = sign_deposit(send_sk, &send_id, &msg_id, &nonce).unwrap();
    let hd = HostDeposit {
        send_id,
        msg_id,
        ttl_windows: 240,
        shard_index,
        shard_total,
        nonce,
        ct,
        sig: *sig.as_bytes(),
    };
    let sealed = mt_crypto::seal_to(host_kem_pk, &hd.to_bytes()).unwrap();
    ProxyForward {
        host_addr: host_overlay,
        sealed,
    }
}

#[tokio::test]
async fn offline_delivery_all_via_couriers_host_never_sees_b() {
    // host + deposit courier + fetch courier (distinct). B registers AND fetches through
    // couriers: the host does NOT see B at registration or at fetch.
    let host = PostmanServer::bind("127.0.0.1:0".parse().unwrap())
        .await
        .unwrap();
    let host_addr = host.local_addr().unwrap();
    let host_kem = host.muq().host_kem_pubkey();
    let dep_courier = PostmanServer::bind("127.0.0.1:0".parse().unwrap())
        .await
        .unwrap();
    let dep_addr = dep_courier.local_addr().unwrap();
    let recv_courier = PostmanServer::bind("127.0.0.1:0".parse().unwrap())
        .await
        .unwrap();
    let recv_addr = recv_courier.local_addr().unwrap();
    let host_overlay: OverlayAddr = [0xA0u8; 32];
    dep_courier.muq().add_proxy_route(host_overlay, host_addr);
    recv_courier.muq().add_proxy_route(host_overlay, host_addr);
    tokio::spawn(host.run());
    tokio::spawn(dep_courier.run());
    tokio::spawn(recv_courier.run());

    let recv_id = [0x71u8; 32];
    let send_id = [0x51u8; 32];
    let (q, recv_sk, send_sk) = make_queue(recv_id, send_id);

    // B registers the queue THROUGH the fetch courier (the host sees the courier, not B).
    let b_reg = with_timeout(MuqClient::connect(recv_addr)).await.unwrap();
    assert!(
        with_timeout(b_reg.register_via_courier(host_overlay, &host_kem, &q))
            .await
            .unwrap()
    );
    drop(b_reg);

    // A puts a deposit through the deposit courier while B is closed.
    let msg_id = [0x5Au8; 16];
    let ct = b"sealed-e2e-for-sleeping-B".to_vec();
    let pf = build_deposit(
        send_id,
        &send_sk,
        msg_id,
        0,
        1,
        ct.clone(),
        host_overlay,
        &host_kem,
    );
    let a = with_timeout(MuqClient::connect(dep_addr)).await.unwrap();
    assert!(with_timeout(a.deposit_via_proxy(&pf)).await.unwrap());

    // B fetches THROUGH the fetch courier: the envelope arrived, the host did not see B.
    let b = with_timeout(MuqClient::connect(recv_addr)).await.unwrap();
    let resp = with_timeout(b.subscribe_via_courier(host_overlay, &host_kem, recv_id, &recv_sk))
        .await
        .unwrap();
    assert_eq!(resp.items.len(), 1, "shard in buffer");
    assert_eq!(resp.items[0].ct, ct);

    // DEV-049(a) §593: drop-on-ACK: the buffer is held until B acknowledges (transit survives
    // failure of the courier->B leg). B acknowledges receipt, and ONLY then does the host drop the buffer.
    let ack_cli = with_timeout(MuqClient::connect(recv_addr)).await.unwrap();
    assert!(
        with_timeout(ack_cli.ack_via_courier(host_overlay, &host_kem, recv_id, &recv_sk))
            .await
            .unwrap(),
        "ack went through the courier"
    );
    let b2 = with_timeout(MuqClient::connect(recv_addr)).await.unwrap();
    let resp2 = with_timeout(b2.subscribe_via_courier(host_overlay, &host_kem, recv_id, &recv_sk))
        .await
        .unwrap();
    assert!(
        resp2.items.is_empty(),
        "after ack the buffer is dropped (drop-on-ack §593)"
    );
}

#[tokio::test]
async fn durability_rs_2of3_via_couriers() {
    // 3 hosts + 1 courier (route to all). B registers+fetches through the courier; RS(2,3)
    // survives one host going down.
    let courier = PostmanServer::bind("127.0.0.1:0".parse().unwrap())
        .await
        .unwrap();
    let courier_addr = courier.local_addr().unwrap();
    let mut host_addrs = Vec::new();
    let mut host_overlays: Vec<OverlayAddr> = Vec::new();
    let mut host_kems = Vec::new();
    for i in 0..3u8 {
        let h = PostmanServer::bind("127.0.0.1:0".parse().unwrap())
            .await
            .unwrap();
        let a = h.local_addr().unwrap();
        let ov: OverlayAddr = [0xC0 + i; 32];
        courier.muq().add_proxy_route(ov, a);
        host_addrs.push(a);
        host_overlays.push(ov);
        host_kems.push(h.muq().host_kem_pubkey());
        tokio::spawn(h.run());
    }
    tokio::spawn(courier.run());

    let recv_id = [0x71u8; 32];
    let send_id = [0x51u8; 32];
    let (q, recv_sk, send_sk) = make_queue(recv_id, send_id);

    // B registers the same queue on all three hosts through the courier.
    for i in 0..3usize {
        let reg = with_timeout(MuqClient::connect(courier_addr))
            .await
            .unwrap();
        assert!(
            with_timeout(reg.register_via_courier(host_overlays[i], &host_kems[i], &q))
                .await
                .unwrap()
        );
    }

    // A spreads RS(2,3) across the three hosts through the courier.
    let msg_id = [0x5Au8; 16];
    let ct = b"a-long-enough-sealed-envelope-across-three-hosts".to_vec();
    let shards = rs_split(&ct, 2, 3).unwrap();
    let a = with_timeout(MuqClient::connect(courier_addr))
        .await
        .unwrap();
    for i in 0..3usize {
        let pf = build_deposit(
            send_id,
            &send_sk,
            msg_id,
            i as u8,
            3,
            shards[i].clone(),
            host_overlays[i],
            &host_kems[i],
        );
        assert!(with_timeout(a.deposit_via_proxy(&pf)).await.unwrap());
    }

    // B fetches ONLY from host0/host1 (host2 is "down") through the courier.
    let mut recovered: Vec<Option<Vec<u8>>> = vec![None; 3];
    for i in 0..2usize {
        let b = with_timeout(MuqClient::connect(courier_addr))
            .await
            .unwrap();
        let resp = with_timeout(b.subscribe_via_courier(
            host_overlays[i],
            &host_kems[i],
            recv_id,
            &recv_sk,
        ))
        .await
        .unwrap();
        assert_eq!(resp.items.len(), 1);
        let it = &resp.items[0];
        recovered[it.shard_index as usize] = Some(it.ct.clone());
    }
    let out = rs_reconstruct(recovered, 2, 3).unwrap();
    assert_eq!(
        &out[..ct.len()],
        &ct[..],
        "recovered from 2 hosts through the courier"
    );
}
