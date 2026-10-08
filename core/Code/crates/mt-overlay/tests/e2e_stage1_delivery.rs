//! [C-4] End-to-End Observable Closure for P2P Network Stage 1.
//! Terminal observable output of the "minimal talking stand": A→postman→B→ACK.
//! Transport-agnostic (ConnId instead of a socket); proves the chain is closed:
//! registration → RELAY → DELIVER → receive+dedup → ACK → ACK delivery to the sender.
//! The bytes of the E2E envelope are opaque (payload is checked for equality, not for content).

use mt_crypto::{keypair_from_seed, PublicKey, SecretKey, PUBLIC_KEY_SIZE};
use mt_overlay::challenge::{sign_registration, ChannelHash, Nonce, NONCE_SIZE};
use mt_overlay::dedup::DedupWindow;
use mt_overlay::frame::{FrameType, MsgId, OverlayFrame};
use mt_overlay::postman::{ConnId, Postman, Route};
use mt_overlay::{overlay_addr, OverlayAddr};
use mt_state::{derive_account_id, SUITE_MLDSA65};

struct Device {
    pubkey: [u8; PUBLIC_KEY_SIZE],
    sk: SecretKey,
    overlay: OverlayAddr,
    inbox: DedupWindow,
}

impl Device {
    fn new(seed: u8) -> Self {
        let (pk, sk): (PublicKey, SecretKey) = keypair_from_seed(&[seed; 32]).unwrap();
        let pubkey = *pk.as_bytes();
        let overlay = overlay_addr(&derive_account_id(SUITE_MLDSA65, &pubkey));
        Self {
            pubkey,
            sk,
            overlay,
            inbox: DedupWindow::default(),
        }
    }

    fn reg_proof(&self, nonce: &Nonce, ch: &ChannelHash) -> mt_crypto::Signature {
        sign_registration(&self.sk, &self.overlay, nonce, ch).unwrap()
    }
}

fn channel_hash_for(conn: ConnId) -> ChannelHash {
    let mut ch = [0u8; 32];
    ch[..8].copy_from_slice(&conn.to_le_bytes());
    ch
}

fn register(postman: &mut Postman, dev: &Device, conn: ConnId, nonce_seed: u8) -> OverlayAddr {
    let nonce: Nonce = [nonce_seed; NONCE_SIZE];
    let ch = channel_hash_for(conn);
    let sig = dev.reg_proof(&nonce, &ch);
    postman
        .register(conn, &dev.pubkey, &nonce, &ch, &sig)
        .expect("valid registration")
}

#[test]
fn e2e_full_journey_a_to_b_and_ack_back() {
    let alice = Device::new(0xA1);
    let mut bob = Device::new(0xB2);
    let mut postman = Postman::new();
    let (conn_a, conn_b): (ConnId, ConnId) = (1, 2);

    let addr_a = register(&mut postman, &alice, conn_a, 0x11);
    let addr_b = register(&mut postman, &bob, conn_b, 0x22);
    assert_eq!(addr_a, alice.overlay);
    assert_eq!(addr_b, bob.overlay);

    let sealed: Vec<u8> = b"opaque-e2e-ratchet-envelope".to_vec();
    let msg_id: MsgId = [0x5A; 16];
    let relay = OverlayFrame {
        frame_type: FrameType::Relay,
        dst_overlay: addr_b,
        src_overlay: addr_a,
        msg_id,
        payload: sealed.clone(),
    };
    let wire = relay.to_bytes();
    let relay = OverlayFrame::decode(&wire).unwrap();

    let delivered = match postman.route(conn_a, relay) {
        Route::Deliver { conn, frame } => {
            assert_eq!(conn, conn_b);
            assert_eq!(frame.frame_type, FrameType::Deliver);
            frame
        },
        other => panic!("expected Deliver, got {other:?}"),
    };

    assert!(bob.inbox.check_and_insert(&delivered.msg_id));
    assert_eq!(
        delivered.payload, sealed,
        "B received exactly the envelope that A sent"
    );

    let ack = OverlayFrame {
        frame_type: FrameType::Ack,
        dst_overlay: addr_a,
        src_overlay: addr_b,
        msg_id: delivered.msg_id,
        payload: Vec::new(),
    };
    match postman.route(conn_b, ack) {
        Route::AckToSender { conn, frame } => {
            assert_eq!(conn, conn_a);
            assert_eq!(frame.msg_id, msg_id, "A received the ACK for its own message");
        },
        other => panic!("expected AckToSender, got {other:?}"),
    }

    assert!(
        !bob.inbox.check_and_insert(&msg_id),
        "duplicate dropped by dedup"
    );
}

#[test]
fn e2e_offline_recipient_buffers_then_no_hijack() {
    let alice = Device::new(0xA1);
    let bob = Device::new(0xB2);
    let mut postman = Postman::new();
    let addr_a = register(&mut postman, &alice, 1, 0x11);

    let relay = OverlayFrame {
        frame_type: FrameType::Relay,
        dst_overlay: bob.overlay,
        src_overlay: addr_a,
        msg_id: [0x01; 16],
        payload: b"for-sleeping-bob".to_vec(),
    };
    assert!(matches!(postman.route(1, relay), Route::Buffer { .. }));

    let nonce: Nonce = [0x33; NONCE_SIZE];
    let ch = channel_hash_for(9);
    let forged = sign_registration(&alice.sk, &bob.overlay, &nonce, &ch).unwrap();
    assert_eq!(postman.register(9, &bob.pubkey, &nonce, &ch, &forged), None);
}
