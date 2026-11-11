//! Stage 5 (second front) — Tier-1 recovery end-to-end: seed → history_key → ArchiveSyncRequest
//! (from_block_seq=0) → full archive → direct decrypt under history_key. All own devices share one
//! history_key, so recovery needs no reseal (spec §195-203). The archive is returned in full and can
//! be verified against the anchor (Stage 7).

use mt_messenger_e2e::archive::{
    block_hash, history_key, open_block, seal_block, HistoryBlock, HistoryItem, DIR_IN, DIR_OUT,
};
use mt_messenger_e2e::archive_sync::{
    build_signed_request, encode_request, parse_request, verify_request,
};
use mt_messenger_e2e::crypto::dsa_pub_from_seed;
use mt_messenger_e2e::handshake::account_id;
use mt_messenger_e2e::merkle::archive_root;
use mt_messenger_e2e::reconcile::{reconcile, select_for_sync, ArchiveIndex};

const ENTROPY: [u8; 32] = [0x55u8; 32];
const ACCOUNT_SEED: [u8; 32] = [0x77u8; 32];
const DEV_A: [u8; 16] = [0x01u8; 16];
const DEV_B: [u8; 16] = [0x02u8; 16];

fn seal(hk: &[u8; 32], acct: &[u8; 32], dev: &[u8; 16], seq: u64, tag: u8, body: &[u8]) -> Vec<u8> {
    let b = HistoryBlock {
        block_seq: seq,
        items: vec![HistoryItem {
            conv_id: [tag; 32],
            dir: if seq % 2 == 0 { DIR_OUT } else { DIR_IN },
            send_time: 1000 + seq,
            content: body.to_vec(),
        }],
    };
    seal_block(hk, acct, dev, &b)
}

#[test]
fn tier1_full_recovery_from_own_device() {
    let hk = history_key(&ENTROPY);
    let account_pub = dsa_pub_from_seed(&ACCOUNT_SEED).unwrap();
    let acct = account_id(&account_pub);

    // A live own device stores the full archive (two writers, several blocks).
    let stored = vec![
        seal(&hk, &acct, &DEV_A, 0, 0xa0, b"first"),
        seal(&hk, &acct, &DEV_A, 1, 0xa1, b"second"),
        seal(&hk, &acct, &DEV_B, 0, 0xb0, b"third"),
        seal(&hk, &acct, &DEV_B, 1, 0xb1, b"fourth"),
    ];
    let mut full = ArchiveIndex::new();
    for s in &stored {
        full.ingest_sealed(&hk, &acct, s);
    }

    // A fresh device: 24 words → same entropy → same history_key; account_key re-derived from the seed.
    let hk_new = history_key(&ENTROPY);
    assert_eq!(
        hk_new, hk,
        "history_key identical across own devices (shared seed)"
    );

    // Onboarding request: from_block_seq = 0 → the whole archive.
    let req = build_signed_request(&ACCOUNT_SEED, &acct, 0, &[0x09u8; 16], 1000).unwrap();
    let wire = encode_request(&req).unwrap();
    let parsed = parse_request(&wire).unwrap();
    assert!(
        verify_request(&parsed, &account_pub, 1000),
        "own-seed request authorizes"
    );
    assert_eq!(parsed.from_block_seq, 0);

    // Responder returns as-stored blocks with block_seq ≥ 0 (the full archive), canonical order.
    let response = select_for_sync(&stored, parsed.from_block_seq);
    assert_eq!(response.len(), 4);

    // Fresh device reconciles and decrypts directly under history_key — no reseal.
    let mut fresh = ArchiveIndex::new();
    let report = reconcile(&mut fresh, &hk_new, &acct, &response);
    assert_eq!(report.new, 4);
    assert_eq!(report.invalid, 0);

    // Full recovery: identical ArchiveRoot, and every block decrypts to its original content.
    assert_eq!(fresh.archive_root(), full.archive_root());
    let mut recovered_bodies = vec![];
    for s in &response {
        let blk = open_block(&hk_new, &acct, s).expect("decrypts under history_key");
        assert_eq!(block_hash(&blk).len(), 32);
        recovered_bodies.push(blk.items[0].content.clone());
    }
    recovered_bodies.sort();
    let mut expect: Vec<Vec<u8>> = [
        b"first".to_vec(),
        b"second".to_vec(),
        b"third".to_vec(),
        b"fourth".to_vec(),
    ]
    .to_vec();
    expect.sort();
    assert_eq!(recovered_bodies, expect);
    assert!(archive_root(&[block_hash(
        &open_block(&hk_new, &acct, &response[0]).unwrap()
    )])
    .is_some());
}

#[test]
fn foreign_seed_cannot_request() {
    let account_pub = dsa_pub_from_seed(&ACCOUNT_SEED).unwrap();
    let acct = account_id(&account_pub);
    let req = build_signed_request(&ACCOUNT_SEED, &acct, 0, &[0x09u8; 16], 1000).unwrap();
    // A different account's pubkey does not authorize this request (archive is always one's own).
    let other_pub = dsa_pub_from_seed(&[0x88u8; 32]).unwrap();
    assert!(!verify_request(&req, &other_pub, 1000));
}
