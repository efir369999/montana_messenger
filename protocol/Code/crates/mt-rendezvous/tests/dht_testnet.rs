//! Running test of Stage 4: node A puts a rendezvous record into the DHT, node B finds it with the same
//! key, WITHOUT a hardcoded address. A local Testnet DHT (mainline) stands in for the real
//! BitTorrent network. Proves that removing the postman's hardcoded address works.

use mainline::{Dht, Testnet};
use mt_rendezvous::dht::RvDht;
use mt_rendezvous::{
    derive_dht_seed, derive_salt, dht_pubkey, dht_signing_key, Endpoint, RendezvousRecord,
    EP_RELAY_CIRCUIT,
};

fn sample_record() -> RendezvousRecord {
    RendezvousRecord {
        overlay_addr: [0xAB; 32],
        endpoints: vec![Endpoint {
            kind: EP_RELAY_CIRCUIT,
            addr: vec![0x7F, 0x00, 0x00, 0x01, 0x21, 0x00], // 127.0.0.1:8448 example
        }],
        pq_hint: [0xCD; 32],
        seq: 1,
        valid_until: 9_999_999,
    }
}

#[test]
fn two_nodes_find_each_other_via_dht_no_hardcoded_addr() {
    // Local DHT of 10 nodes (bootstrap for A and B).
    let testnet = Testnet::new(10).expect("testnet");

    let dht_a = Dht::builder()
        .bootstrap(&testnet.bootstrap)
        .build()
        .expect("dht A");
    let dht_b = Dht::builder()
        .bootstrap(&testnet.bootstrap)
        .build()
        .expect("dht B");
    let rv_a = RvDht::from_dht(dht_a);
    let rv_b = RvDht::from_dht(dht_b);

    // A derives dht_key from its master_seed and puts the "I am here" record.
    let master = [0x42u8; 64];
    let dht_seed = derive_dht_seed(&master);
    let dk = dht_pubkey(&dht_signing_key(&dht_seed));
    let salt = derive_salt(&[0x33; 32], 7); // the pair's shared session_id
    let record = sample_record();

    rv_a.put(&dht_seed, &salt, record.seq, &record)
        .expect("A put into DHT");

    // B knows dk (from the E2E session) + the same salt, so it finds the record via the DHT.
    let got = rv_b.get(&dk, &salt, 0).expect("B found the record via DHT");
    assert_eq!(
        got, record,
        "record found byte-exact, without a hardcoded address"
    );
    assert_eq!(got.endpoints[0].kind, EP_RELAY_CIRCUIT);
}

#[test]
fn wrong_salt_finds_nothing() {
    let testnet = Testnet::new(10).expect("testnet");
    let dht_a = Dht::builder()
        .bootstrap(&testnet.bootstrap)
        .build()
        .unwrap();
    let dht_b = Dht::builder()
        .bootstrap(&testnet.bootstrap)
        .build()
        .unwrap();
    let rv_a = RvDht::from_dht(dht_a);
    let rv_b = RvDht::from_dht(dht_b);

    let dht_seed = derive_dht_seed(&[0x42u8; 64]);
    let dk = dht_pubkey(&dht_signing_key(&dht_seed));
    let salt = derive_salt(&[0x33; 32], 7);
    rv_a.put(&dht_seed, &salt, 1, &sample_record()).unwrap();

    // different salt (different epoch) → a different target → nothing
    let other_salt = derive_salt(&[0x33; 32], 8);
    assert!(rv_b.get(&dk, &other_salt, 0).is_none());
}

#[test]
fn presigned_batch_republished_by_relay_without_secret() {
    // The leaf pre-signs a batch with its dht_key (offline); the postman (WITHOUT the leaf secret)
    // re-puts the record into the DHT; the reader finds it byte for byte. The secret never left the leaf.
    use mt_rendezvous::dht::{prepare_batch, RvDht};
    use mt_rendezvous::{
        derive_dht_seed, derive_salt, dht_pubkey, dht_signing_key, Endpoint, RendezvousRecord,
        EP_DIRECT_V4,
    };

    let testnet = Testnet::new(10).unwrap();
    let dht_relay = Dht::builder()
        .bootstrap(&testnet.bootstrap)
        .build()
        .unwrap();
    let dht_reader = Dht::builder()
        .bootstrap(&testnet.bootstrap)
        .build()
        .unwrap();
    let rv_relay = RvDht::from_dht(dht_relay); // postman: does NOT hold the leaf secret
    let rv_reader = RvDht::from_dht(dht_reader);

    // Leaf: dht_key secret + batch pre-signature.
    let master = [0x33u8; 32];
    let dht_seed = derive_dht_seed(&master);
    let dk = dht_pubkey(&dht_signing_key(&dht_seed));
    let session_id = [0x44u8; 32];
    let salt = derive_salt(&session_id, 7);
    let rec = RendezvousRecord {
        overlay_addr: [0xAB; 32],
        endpoints: vec![Endpoint {
            kind: EP_DIRECT_V4,
            addr: vec![203, 0, 113, 5, 0x20, 0xFC], // 203.0.113.5:8444
        }],
        pq_hint: [0xCD; 32],
        seq: 0,
        valid_until: 9_999,
    };
    let batch = prepare_batch(&dht_seed, &salt, 1, vec![rec]).unwrap();
    assert_eq!(batch.len(), 1);
    assert_eq!(batch[0].seq, 1);
    assert_eq!(batch[0].dk, dk);

    // The postman re-puts the pre-signed record.
    rv_relay.put_presigned(&batch[0]).unwrap();

    // The reader finds the record and resolves the physical address FROM the DHT record (not from config).
    let got = rv_reader.get(&dk, &salt, 0).expect("record found");
    assert_eq!(got.seq, 1);
    assert_eq!(got.overlay_addr, [0xAB; 32]);
    let sock = mt_rendezvous::resolve_endpoint(&got.endpoints[0]).expect("v4 resolve");
    assert_eq!(sock.to_string(), "203.0.113.5:8444");
}

#[test]
fn expired_record_filtered_by_valid_until() {
    // F-5: a record with valid_until in the past relative to now: get returns None
    // (freshness wall §593 R2: a dead leaf does not resolve).
    use mt_rendezvous::dht::RvDht;
    use mt_rendezvous::{
        derive_dht_seed, derive_salt, dht_pubkey, dht_signing_key, Endpoint, RendezvousRecord,
        EP_DIRECT_V4,
    };

    let testnet = Testnet::new(10).unwrap();
    let rv_a = RvDht::from_dht(
        Dht::builder()
            .bootstrap(&testnet.bootstrap)
            .build()
            .unwrap(),
    );
    let rv_b = RvDht::from_dht(
        Dht::builder()
            .bootstrap(&testnet.bootstrap)
            .build()
            .unwrap(),
    );

    let dht_seed = derive_dht_seed(&[0x55u8; 32]);
    let dk = dht_pubkey(&dht_signing_key(&dht_seed));
    let salt = derive_salt(&[0x66u8; 32], 3);
    let rec = RendezvousRecord {
        overlay_addr: [0x77; 32],
        endpoints: vec![Endpoint {
            kind: EP_DIRECT_V4,
            addr: vec![203, 0, 113, 9, 0x20, 0xFC],
        }],
        pq_hint: [0x88; 32],
        seq: 1,
        valid_until: 100, // validity window up to unix=100
    };
    rv_a.put(&dht_seed, &salt, 1, &rec).unwrap();

    // now=50 (inside the window) → found
    assert!(
        rv_b.get(&dk, &salt, 50).is_some(),
        "within valid_until: found"
    );
    // now=200 (after valid_until) → dropped
    assert!(
        rv_b.get(&dk, &salt, 200).is_none(),
        "expired: does not resolve (R2)"
    );
}
