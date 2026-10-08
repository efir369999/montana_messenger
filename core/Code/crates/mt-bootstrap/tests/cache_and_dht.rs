//! Running tests of Stage 5: the learned-node cache on disk + resolving a stale QR endpoint
//! via the DHT by dk (§618, tied to Stage 4).

use std::net::SocketAddr;

use mainline::{Dht, Testnet};
use mt_bootstrap::{QRBootstrap, Seed, SeedList, QR_KIND_DIRECT_V6};
use mt_rendezvous::dht::RvDht;
use mt_rendezvous::{
    derive_dht_seed, derive_salt, dht_pubkey, dht_signing_key, Endpoint, RendezvousRecord,
    EP_DIRECT_V4,
};

#[test]
fn cache_save_load_roundtrip_on_disk() {
    let list = SeedList {
        seeds: vec![
            Seed::from_socket("203.0.113.7:8444".parse::<SocketAddr>().unwrap()),
            Seed::from_socket("[2001:db8::1]:9000".parse::<SocketAddr>().unwrap()),
        ],
    };
    let path = std::env::temp_dir().join("mt_bootstrap_cache_roundtrip.bin");
    list.save(&path).unwrap();
    let loaded = SeedList::load(&path).unwrap();
    assert_eq!(
        loaded, list,
        "learned-node cache survives disk byte-exact"
    );
    std::fs::remove_file(&path).ok();
}

#[test]
fn expired_qr_resolves_current_address_via_dht() {
    // §618: after expires the client ignores the QR ep and looks up the current address via the DHT by dk.
    let testnet = Testnet::new(10).unwrap();
    let rv_friend = RvDht::from_dht(
        Dht::builder()
            .bootstrap(&testnet.bootstrap)
            .build()
            .unwrap(),
    );
    let rv_new = RvDht::from_dht(
        Dht::builder()
            .bootstrap(&testnet.bootstrap)
            .build()
            .unwrap(),
    );

    // Friend: dht_key + publishes the postman's current address to the DHT.
    let dht_seed = derive_dht_seed(&[0x51u8; 32]);
    let dk = dht_pubkey(&dht_signing_key(&dht_seed));
    let session_id = [0x62u8; 32]; // knowledge binding (from the E2E session with the friend)
    let salt = derive_salt(&session_id, 0);
    let fresh = RendezvousRecord {
        overlay_addr: [0x77; 32],
        endpoints: vec![Endpoint {
            kind: EP_DIRECT_V4,
            addr: vec![203, 0, 113, 50, 0x20, 0xFC], // 203.0.113.50:8444 (current)
        }],
        pq_hint: [0x88; 32],
        seq: 1,
        valid_until: 9_999,
    };
    rv_friend.put(&dht_seed, &salt, 1, &fresh).unwrap();

    // New phone: the friend's QR is stale (expires=100) but carries dk.
    let qr = QRBootstrap {
        dk,
        expires: 100,
        ep_kind: QR_KIND_DIRECT_V6,
        ep: {
            let mut e = vec![0u8; 16];
            e[15] = 9; // old (stale) address
            e.extend_from_slice(&1u16.to_be_bytes());
            e
        },
    };
    // now=500 > expires → the direct endpoint is not taken.
    assert!(qr.current_endpoint(500).is_none(), "QR is stale");

    // Resolve via the DHT by dk from the QR (+ salt from the binding) → current address.
    let got = rv_new
        .get(&qr.dk, &salt, 500)
        .expect("DHT returned the current address");
    let sock = mt_rendezvous::resolve_endpoint(&got.endpoints[0]).unwrap();
    assert_eq!(
        sock.to_string(),
        "203.0.113.50:8444",
        "new node found the friend's live address"
    );
}
