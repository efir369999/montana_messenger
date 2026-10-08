//! Postman — routing of overlay frames between registered connections
//! (Stage 1, mechanics steps 0/3). Transport-agnostic logic: connections are abstract
//! (ConnId), integration with QUIC is a separate layer. Not consensus state.

use std::collections::HashMap;

use crate::challenge::{verify_registration, ChannelHash, Nonce};
use crate::frame::{FrameType, OverlayFrame};
use crate::OverlayAddr;
use mt_crypto::{Signature, PUBLIC_KEY_SIZE};

pub type ConnId = u64;

/// Where the postman directs a frame after parsing.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Route {
    /// Forward to the live connection of the recipient as DELIVER.
    Deliver { conn: ConnId, frame: OverlayFrame },
    /// The recipient is offline: into the incoming buffer (Stage 2 store-and-forward).
    Buffer { frame: OverlayFrame },
    /// ACK back to the sender (if its connection is alive).
    AckToSender { conn: ConnId, frame: OverlayFrame },
    /// Drop (the ACK recipient is not online / irrelevant).
    Drop,
}

#[derive(Default)]
pub struct Postman {
    // overlay_addr -> live connection (filled only after verify_registration)
    by_addr: HashMap<OverlayAddr, ConnId>,
    by_conn: HashMap<ConnId, OverlayAddr>,
}

impl Postman {
    pub fn new() -> Self {
        Self::default()
    }

    /// Step 0: register a connection after a valid RegProof.
    /// Returns the confirmed overlay_addr or None (signature/binding is wrong).
    ///
    /// Transport layer contract (D2): `nonce` is fresh CSPRNG on every registration;
    /// `channel_hash` is a binding to the current connection (TLS-Exporter/Noise handshake-hash).
    /// Cross-connection replay is closed by `channel_hash` (R4); intra-connection by a fresh `nonce`.
    ///
    /// S2: when one `overlay_addr` is registered by two connections the last one wins
    /// (the route by addr goes to the new conn). This is self-inflicted multi-device use of one identity
    /// (a foreign addr cannot be registered — a signature is needed), not an attack.
    pub fn register(
        &mut self,
        conn: ConnId,
        account_pubkey: &[u8; PUBLIC_KEY_SIZE],
        nonce: &Nonce,
        channel_hash: &ChannelHash,
        sig: &Signature,
    ) -> Option<OverlayAddr> {
        let addr = verify_registration(account_pubkey, nonce, channel_hash, sig)?;
        if let Some(prev) = self.by_conn.insert(conn, addr) {
            if prev != addr {
                self.by_addr.remove(&prev);
            }
        }
        self.by_addr.insert(addr, conn);
        Some(addr)
    }

    pub fn deregister(&mut self, conn: ConnId) {
        if let Some(addr) = self.by_conn.remove(&conn) {
            if self.by_addr.get(&addr) == Some(&conn) {
                self.by_addr.remove(&addr);
            }
        }
    }

    pub fn is_registered(&self, conn: ConnId) -> bool {
        self.by_conn.contains_key(&conn)
    }

    /// Step 3: route of an incoming frame. `from` is the source connection (for ACK/dedup).
    /// src_overlay is not authenticated (spec): route strictly by dst.
    pub fn route(&self, from: ConnId, frame: OverlayFrame) -> Route {
        match frame.frame_type {
            FrameType::Relay => match self.by_addr.get(&frame.dst_overlay) {
                Some(&conn) => Route::Deliver {
                    conn,
                    frame: OverlayFrame {
                        frame_type: FrameType::Deliver,
                        ..frame
                    },
                },
                None => Route::Buffer { frame },
            },
            // ACK from the recipient back to the sender by dst_overlay.
            // S9: ACK is ephemeral — if the sender is offline, the ACK is dropped,
            // NOT buffered (the Stage 2 buffer is for content, not for acknowledgments).
            FrameType::Ack => match self.by_addr.get(&frame.dst_overlay) {
                Some(&conn) => Route::AckToSender { conn, frame },
                None => Route::Drop,
            },
            // DELIVER is an outgoing postman type, it must not be incoming.
            FrameType::Deliver => {
                let _ = from;
                Route::Drop
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::challenge::{sign_registration, NONCE_SIZE};
    use crate::{overlay_addr, OverlayAddr};
    use mt_crypto::{keypair_from_seed, PublicKey, SecretKey};
    use mt_state::{derive_account_id, SUITE_MLDSA65};

    fn ident(seed: u8) -> ([u8; PUBLIC_KEY_SIZE], SecretKey, OverlayAddr) {
        let (pk, sk): (PublicKey, SecretKey) = keypair_from_seed(&[seed; 32]).unwrap();
        let pkb = *pk.as_bytes();
        let addr = overlay_addr(&derive_account_id(SUITE_MLDSA65, &pkb));
        (pkb, sk, addr)
    }

    fn reg(p: &mut Postman, conn: ConnId, seed: u8) -> OverlayAddr {
        let (pkb, sk, _addr) = ident(seed);
        let nonce = [seed; NONCE_SIZE];
        let ch = [0xC0; 32];
        let sig = sign_registration(
            &sk,
            &overlay_addr(&derive_account_id(SUITE_MLDSA65, &pkb)),
            &nonce,
            &ch,
        )
        .unwrap();
        p.register(conn, &pkb, &nonce, &ch, &sig).expect("register")
    }

    #[test]
    fn relay_to_registered_becomes_deliver() {
        let mut p = Postman::new();
        let a = reg(&mut p, 1, 0xA1);
        let b = reg(&mut p, 2, 0xB2);
        let frame = OverlayFrame {
            frame_type: FrameType::Relay,
            dst_overlay: b,
            src_overlay: a,
            msg_id: [0x01; 16],
            payload: b"x".to_vec(),
        };
        match p.route(1, frame) {
            Route::Deliver { conn, frame } => {
                assert_eq!(conn, 2);
                assert_eq!(frame.frame_type, FrameType::Deliver);
            },
            other => panic!("expected Deliver, got {other:?}"),
        }
    }

    #[test]
    fn relay_to_unknown_buffers() {
        let mut p = Postman::new();
        let a = reg(&mut p, 1, 0xA1);
        let frame = OverlayFrame {
            frame_type: FrameType::Relay,
            dst_overlay: [0xEE; 32],
            src_overlay: a,
            msg_id: [0x01; 16],
            payload: b"x".to_vec(),
        };
        assert!(matches!(p.route(1, frame), Route::Buffer { .. }));
    }

    #[test]
    fn forged_registration_rejected_and_no_hijack() {
        let mut p = Postman::new();
        let (pkb, _sk, _addr) = ident(0xA1);
        let (_pk2, sk2, _a2) = ident(0xB2);
        // Signature by B's key under A's address: the binding will not match.
        let nonce = [0x01; NONCE_SIZE];
        let ch = [0xC0; 32];
        let addr_a = overlay_addr(&derive_account_id(SUITE_MLDSA65, &pkb));
        let sig = sign_registration(&sk2, &addr_a, &nonce, &ch).unwrap();
        assert_eq!(p.register(9, &pkb, &nonce, &ch, &sig), None);
        assert!(!p.is_registered(9));
    }

    #[test]
    fn ack_to_offline_sender_is_dropped_not_buffered() {
        // S9: ACK to an unknown/offline dst — Drop, not Buffer.
        let mut p = Postman::new();
        let _b = reg(&mut p, 2, 0xB2);
        let frame = OverlayFrame {
            frame_type: FrameType::Ack,
            dst_overlay: [0xEE; 32], // sender is offline
            src_overlay: [0; 32],
            msg_id: [0x09; 16],
            payload: Vec::new(),
        };
        assert!(matches!(p.route(2, frame), Route::Drop));
    }

    #[test]
    fn ack_to_online_sender_forwarded() {
        let mut p = Postman::new();
        let a = reg(&mut p, 1, 0xA1);
        let _b = reg(&mut p, 2, 0xB2);
        let frame = OverlayFrame {
            frame_type: FrameType::Ack,
            dst_overlay: a,
            src_overlay: [0; 32],
            msg_id: [0x09; 16],
            payload: Vec::new(),
        };
        assert!(matches!(
            p.route(2, frame),
            Route::AckToSender { conn: 1, .. }
        ));
    }

    #[test]
    fn deregister_clears_routing() {
        let mut p = Postman::new();
        let _a = reg(&mut p, 1, 0xA1);
        let b = reg(&mut p, 2, 0xB2);
        p.deregister(2);
        let frame = OverlayFrame {
            frame_type: FrameType::Relay,
            dst_overlay: b,
            src_overlay: [0; 32],
            msg_id: [0x01; 16],
            payload: b"x".to_vec(),
        };
        assert!(matches!(p.route(1, frame), Route::Buffer { .. }));
    }
}
