//! Stage 7 — blind delivery: rotating queue labels.
//! routing_secret from the session root; the session label rotates every τ₁ window;
//! the inbox label is stable (f of account_id) — provides wake-push.

use sha2::{Digest, Sha256};

use crate::kdf::{hkdf_sha256, hmac_sha256};

pub const LABEL_LEN: usize = 16;
pub const TAU1_SECONDS: u64 = 60;

pub const DIR_INITIATOR_TO_RESPONDER: u8 = 0x00;
pub const DIR_RESPONDER_TO_INITIATOR: u8 = 0x01;

/// routing_secret = HKDF(salt=0×32, IKM=initial_root_key, info="mt-routing", 32).
pub fn routing_secret(initial_root_key: &[u8; 32]) -> [u8; 32] {
    let okm = hkdf_sha256(&[0u8; 32], initial_root_key, b"mt-routing", 32);
    let mut out = [0u8; 32];
    out.copy_from_slice(&okm);
    out
}

/// Window index W = ⌊unix_time / 60⌋.
pub fn window_index(unix_time: u64) -> u64 {
    unix_time / TAU1_SECONDS
}

/// session_label(dir, W) = HMAC(routing_secret, "mt-label"‖0x00‖dir‖W_le8)[0..16].
pub fn session_label(routing_secret: &[u8; 32], dir: u8, window: u64) -> [u8; LABEL_LEN] {
    let mut msg = b"mt-label".to_vec();
    msg.push(0u8);
    msg.push(dir);
    msg.extend_from_slice(&window.to_le_bytes());
    let full = hmac_sha256(routing_secret, &msg);
    let mut out = [0u8; LABEL_LEN];
    out.copy_from_slice(&full[..LABEL_LEN]);
    out
}

/// inbox_label(account_id) = SHA-256("mt-inbox"‖0x00‖account_id)[0..16]. Stable.
pub fn inbox_label(account_id: &[u8; 32]) -> [u8; LABEL_LEN] {
    let mut h = Sha256::new();
    h.update(b"mt-inbox");
    h.update([0u8]);
    h.update(account_id);
    let full: [u8; 32] = h.finalize().into();
    let mut out = [0u8; LABEL_LEN];
    out.copy_from_slice(&full[..LABEL_LEN]);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn label_lengths_and_determinism() {
        let rs = routing_secret(&[0x11; 32]);
        let a = session_label(&rs, DIR_INITIATOR_TO_RESPONDER, 100);
        let b = session_label(&rs, DIR_INITIATOR_TO_RESPONDER, 100);
        assert_eq!(a, b);
        assert_eq!(a.len(), 16);
        assert_eq!(inbox_label(&[0x22; 32]).len(), 16);
    }

    #[test]
    fn labels_rotate_by_window_and_direction() {
        let rs = routing_secret(&[0x11; 32]);
        assert_ne!(
            session_label(&rs, DIR_INITIATOR_TO_RESPONDER, 100),
            session_label(&rs, DIR_INITIATOR_TO_RESPONDER, 101)
        );
        assert_ne!(
            session_label(&rs, DIR_INITIATOR_TO_RESPONDER, 100),
            session_label(&rs, DIR_RESPONDER_TO_INITIATOR, 100)
        );
    }

    #[test]
    fn inbox_label_stable_and_unique() {
        assert_eq!(inbox_label(&[0x22; 32]), inbox_label(&[0x22; 32]));
        assert_ne!(inbox_label(&[0x22; 32]), inbox_label(&[0x23; 32]));
    }

    #[test]
    fn route_label_spec_kat() {
        // Bind production functions to spec hex (Stage 7, "Test vectors"), not re-deriving formulas
        let rs = routing_secret(&[0xAB; 32]);
        assert_eq!(
            hex::encode(rs),
            "5dde1ca30d45f658626b6acfac59f25b39bfc8cbbf9db4250fd60ceb4f6624d1"
        );
        assert_eq!(
            hex::encode(session_label(&rs, DIR_INITIATOR_TO_RESPONDER, 1000)),
            "bb4ca49fe117ff008b3f959f19ec186b"
        );
        assert_eq!(
            hex::encode(session_label(&rs, DIR_RESPONDER_TO_INITIATOR, 1000)),
            "1b4bc34a8901e9cef430c077f9b19d54"
        );
        let acc: [u8; 32] =
            hex::decode("9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21")
                .unwrap()
                .try_into()
                .unwrap();
        assert_eq!(
            hex::encode(inbox_label(&acc)),
            "7d5db70fa1b5f7e7902bba6bbbd626ba"
        );
    }

    #[test]
    fn window_index_boundaries() {
        assert_eq!(window_index(0), 0);
        assert_eq!(window_index(59), 0);
        assert_eq!(window_index(60), 1);
    }
}
