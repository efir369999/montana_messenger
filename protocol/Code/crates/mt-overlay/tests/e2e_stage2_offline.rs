//! [C-4] E2E MUQ (Stage 2): two-hop deposit through an entry-proxy → the host does not link
//! sender<->recipient; RS recovery on shard loss; drop-on-delivery.

use mt_crypto::{keypair_from_seed, PublicKey, SecretKey, PUBLIC_KEY_SIZE};
use mt_overlay::challenge::{ChannelHash, Nonce};
use mt_overlay::erasure::{rs_reconstruct, rs_split};
use mt_overlay::inbox::bucket_len;
use mt_overlay::muq::{
    derive_queue_keypairs, sign_deposit, sign_subscribe, HostDeposit, ProxyForward, Queue,
};
use mt_overlay::queue_host::QueueHost;

fn kp(seed: u8) -> ([u8; PUBLIC_KEY_SIZE], SecretKey) {
    let (pk, sk): (PublicKey, SecretKey) = keypair_from_seed(&[seed; 32]).unwrap();
    (*pk.as_bytes(), sk)
}

#[test]
fn e2e_muq_two_hop_deposit_subscribe_reassemble() {
    // M-1: queue keys are EPHEMERAL per-queue from the session routing_secret (NOT account_key),
    // so the host cannot derive account_id from recv_pubkey.
    let routing_secret = [0x42u8; 32]; // root of the A<->B E2E session
    let ((r_pk, rsk), (s_pk, ssk)) = derive_queue_keypairs(&routing_secret, 0).unwrap();
    let (rpk, spk) = (*r_pk.as_bytes(), *s_pk.as_bytes());
    let mut host = QueueHost::new();
    let q = Queue::generate(rpk, Some(spk), 1000, 64).unwrap();
    let (recv_id, send_id) = (q.recv_id, q.send_id);
    host.register_queue(q, 0);

    // A: message → bucket → RS(2,4) → 4 shards → two hops through the entry-proxy.
    let sealed = b"opaque-pq-double-ratchet-envelope-for-sleeping-bob".to_vec();
    let bucket = bucket_len(sealed.len()).unwrap();
    let mut padded = sealed.clone();
    padded.resize(bucket, 0);
    let shards = rs_split(&padded, 2, 4).unwrap();
    for (i, sh) in shards.iter().enumerate() {
        let nonce: Nonce = [i as u8; 16];
        let sig = sign_deposit(&ssk, &send_id, &[0x5A; 16], &nonce).unwrap();
        let hd = HostDeposit {
            send_id,
            msg_id: [0x5A; 16],
            ttl_windows: 240,
            shard_index: i as u8,
            shard_total: 4,
            nonce,
            ct: sh.clone(),
            sig: *sig.as_bytes(),
        };
        // A → entry-proxy (ProxyForward), proxy → host (sealed HostDeposit).
        let pf_wire = ProxyForward {
            host_addr: [0xEE; 32],
            sealed: hd.to_bytes(),
        }
        .to_bytes();
        let fwd = ProxyForward::decode(&pf_wire).unwrap();
        let hd_at_host = HostDeposit::decode(&fwd.sealed).unwrap();
        host.deposit(&hd_at_host, 100).unwrap(); // the host sees the deposit FROM THE PROXY, not from A
    }

    // B fetch: recv_key signature + channel_hash (F3).
    let nonce: Nonce = [0x07; 16];
    let ch: ChannelHash = [0x0C; 32];
    let sig = sign_subscribe(&rsk, &recv_id, &nonce, &ch).unwrap();
    let stored = host
        .subscribe(&recv_id, &nonce, &ch, &sig)
        .unwrap()
        .to_vec();
    assert_eq!(stored.len(), 4);

    // TERMINAL: lose 2 of 4 → recover.
    let mut opt: Vec<Option<Vec<u8>>> = vec![None; 4];
    opt[1] = Some(stored[1].ct.clone());
    opt[3] = Some(stored[3].ct.clone());
    let recovered = rs_reconstruct(opt, 2, 4).unwrap();
    assert_eq!(
        &recovered[..sealed.len()],
        &sealed[..],
        "B recovered the envelope from 2 of 4"
    );

    host.drop_delivered(&recv_id, &[0x5A; 16]);
    assert_eq!(host.buffer_of(&recv_id).len(), 0);
}

#[test]
fn e2e_muq_cannot_subscribe_foreign_queue() {
    // B signs the recv_id of SOMEONE ELSE'S queue: verification against its recv_pubkey will not match.
    let (rpk, _rsk) = kp(0xB2);
    let (_bpk, bsk) = kp(0xC3); // attacker B with its own key
    let mut host = QueueHost::new();
    let q = Queue::generate(rpk, None, 1000, 64).unwrap();
    let recv_id = q.recv_id;
    host.register_queue(q, 0);
    let nonce: Nonce = [0x07; 16];
    let ch: ChannelHash = [0x0C; 32];
    let sig = sign_subscribe(&bsk, &recv_id, &nonce, &ch).unwrap();
    assert!(host.subscribe(&recv_id, &nonce, &ch, &sig).is_err());
}
