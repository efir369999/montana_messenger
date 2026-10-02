// spec, раздел "Сетевой уровень → Обфускация транспорта → Identity-Bound Tunnel (IBT)"
//
// Online IBT proof:
//   proof = ML-DSA-65_sign(client_sk,
//                          "mt-tunnel-online" || server_node_id ||
//                          floor(W / 2) || online_session_nonce)
//
// Mesh IBT proof (Mesh transport IBT extension):
//   proof = ML-DSA-65_sign(client_sk,
//                          "mt-tunnel-mesh" || peer_node_id ||
//                          floor(cached_W / 2) || mesh_session_nonce)

use alloc::collections::BTreeMap;
use alloc::vec::Vec;

use mt_codec::domain::{TUNNEL_MESH, TUNNEL_ONLINE};
use mt_codec::{write_bytes, write_u64};
use mt_crypto::{hash, sign, verify, CryptoError, PublicKey, SecretKey, Signature};

use crate::error::NetError;

// Re-export для backwards compatibility public API mt-net до Phase B.0 callsites.
pub use mt_codec::domain::TUNNEL_MESH as DOMAIN_TUNNEL_MESH;
pub use mt_codec::domain::TUNNEL_ONLINE as DOMAIN_TUNNEL_ONLINE;

pub const MESH_NONCE_SIZE: usize = 32;
pub const ONLINE_NONCE_SIZE: usize = 32;
pub const MESH_STALENESS_BOUND_TAU1: u64 = 7;
pub const ONLINE_NONCE_RETENTION_SLOTS: u64 = 2;
pub const MAX_ONLINE_NONCES_PER_CLIENT: usize = 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IbtError {
    InvalidSignature,
    StalenessBoundExceeded,
    ReplayedNonce,
    NonceCapacityExceeded,
    CryptoFailure,
}

impl From<CryptoError> for IbtError {
    fn from(_: CryptoError) -> Self {
        IbtError::CryptoFailure
    }
}

impl From<IbtError> for NetError {
    fn from(_: IbtError) -> Self {
        NetError::InvalidPayloadField
    }
}

#[inline]
fn window_slot(window_index: u64) -> u64 {
    window_index / 2
}

pub fn ibt_online_message(
    server_node_id: &[u8; 32],
    window_index: u64,
    online_session_nonce: &[u8; ONLINE_NONCE_SIZE],
) -> Vec<u8> {
    let mut buf = Vec::with_capacity(TUNNEL_ONLINE.len() + 32 + 8 + ONLINE_NONCE_SIZE);
    write_bytes(&mut buf, TUNNEL_ONLINE);
    write_bytes(&mut buf, server_node_id);
    write_u64(&mut buf, window_slot(window_index));
    write_bytes(&mut buf, online_session_nonce);
    buf
}

pub fn ibt_online_proof(
    client_sk: &SecretKey,
    server_node_id: &[u8; 32],
    window_index: u64,
    online_session_nonce: &[u8; ONLINE_NONCE_SIZE],
) -> Result<Signature, IbtError> {
    let msg = ibt_online_message(server_node_id, window_index, online_session_nonce);
    sign(client_sk, &msg).map_err(IbtError::from)
}

pub fn ibt_online_verify(
    client_pk: &PublicKey,
    server_node_id: &[u8; 32],
    current_window: u64,
    online_session_nonce: &[u8; ONLINE_NONCE_SIZE],
    proof: &Signature,
) -> Result<u64, IbtError> {
    // spec: window slot = current ИЛИ previous (acceptable bound)
    let candidates = [current_window, current_window.saturating_sub(2)];
    for &w in &candidates {
        let msg = ibt_online_message(server_node_id, w, online_session_nonce);
        if verify(client_pk, &msg, proof) {
            return Ok(w);
        }
    }
    Err(IbtError::InvalidSignature)
}

#[derive(Debug, Clone)]
pub struct OnlineNonceTracker {
    used_nonces: BTreeMap<[u8; 32], BTreeMap<[u8; ONLINE_NONCE_SIZE], u64>>,
    pub max_used_nonces_per_client: usize,
}

impl OnlineNonceTracker {
    pub fn new() -> Self {
        Self {
            used_nonces: BTreeMap::new(),
            max_used_nonces_per_client: MAX_ONLINE_NONCES_PER_CLIENT,
        }
    }

    pub fn nonce_count(&self, client_pk: &PublicKey) -> usize {
        let client_hash = online_nonce_client_hash(client_pk);
        self.used_nonces
            .get(&client_hash)
            .map(|s| s.len())
            .unwrap_or(0)
    }

    pub fn check_and_insert(
        &mut self,
        client_pk: &PublicKey,
        online_session_nonce: &[u8; ONLINE_NONCE_SIZE],
        current_window: u64,
        accepted_window: u64,
    ) -> Result<(), IbtError> {
        let current_slot = window_slot(current_window);
        let min_live_slot = current_slot.saturating_sub(ONLINE_NONCE_RETENTION_SLOTS - 1);
        let accepted_slot = window_slot(accepted_window);
        let client_hash = online_nonce_client_hash(client_pk);
        let nonces = self.used_nonces.entry(client_hash).or_default();

        nonces.retain(|_, slot| *slot >= min_live_slot);
        if nonces.contains_key(online_session_nonce) {
            return Err(IbtError::ReplayedNonce);
        }
        if nonces.len() >= self.max_used_nonces_per_client {
            return Err(IbtError::NonceCapacityExceeded);
        }

        nonces.insert(*online_session_nonce, accepted_slot);
        Ok(())
    }
}

impl Default for OnlineNonceTracker {
    fn default() -> Self {
        Self::new()
    }
}

fn online_nonce_client_hash(client_pk: &PublicKey) -> [u8; 32] {
    hash(b"mt-online-nonce-client", &[client_pk.as_bytes()])
}

pub fn ibt_mesh_message(
    peer_node_id: &[u8; 32],
    cached_window_index: u64,
    mesh_session_nonce: &[u8; MESH_NONCE_SIZE],
) -> Vec<u8> {
    let mut buf = Vec::with_capacity(TUNNEL_MESH.len() + 32 + 8 + MESH_NONCE_SIZE);
    write_bytes(&mut buf, TUNNEL_MESH);
    write_bytes(&mut buf, peer_node_id);
    write_u64(&mut buf, window_slot(cached_window_index));
    write_bytes(&mut buf, mesh_session_nonce);
    buf
}

pub fn ibt_mesh_proof(
    client_sk: &SecretKey,
    peer_node_id: &[u8; 32],
    cached_window_index: u64,
    mesh_session_nonce: &[u8; MESH_NONCE_SIZE],
) -> Result<Signature, IbtError> {
    let msg = ibt_mesh_message(peer_node_id, cached_window_index, mesh_session_nonce);
    sign(client_sk, &msg).map_err(IbtError::from)
}

pub fn ibt_mesh_verify_with_window(
    client_pk: &PublicKey,
    peer_node_id: &[u8; 32],
    known_window: u64,
    mesh_session_nonce: &[u8; MESH_NONCE_SIZE],
    proof: &Signature,
    tau1_windows: u64,
) -> Result<u64, IbtError> {
    // Backwards-compat fallback API: searches full bound. Prefer
    // ibt_mesh_verify_explicit с явным cached_W из mesh advertisement
    // (per Pass 21 algorithmic complexity audit — O(1) verify path).
    let span = MESH_STALENESS_BOUND_TAU1 * tau1_windows;
    let lo = known_window.saturating_sub(span);
    let hi = known_window;
    let mut w = hi;
    loop {
        let msg = ibt_mesh_message(peer_node_id, w, mesh_session_nonce);
        if verify(client_pk, &msg, proof) {
            return Ok(w);
        }
        if w <= lo {
            break;
        }
        w -= 1;
    }
    Err(IbtError::InvalidSignature)
}

pub fn ibt_mesh_verify_explicit(
    client_pk: &PublicKey,
    peer_node_id: &[u8; 32],
    cached_window_index: u64,
    known_window: u64,
    mesh_session_nonce: &[u8; MESH_NONCE_SIZE],
    proof: &Signature,
    tau1_windows: u64,
) -> Result<u64, IbtError> {
    // O(1) path: cached_W пришёл от sender в plain mesh advertisement;
    // verifier проверяет staleness bound и одну ML-DSA-65 verify.
    let span = MESH_STALENESS_BOUND_TAU1 * tau1_windows;
    if cached_window_index > known_window || cached_window_index < known_window.saturating_sub(span)
    {
        return Err(IbtError::StalenessBoundExceeded);
    }
    let msg = ibt_mesh_message(peer_node_id, cached_window_index, mesh_session_nonce);
    if verify(client_pk, &msg, proof) {
        Ok(cached_window_index)
    } else {
        Err(IbtError::InvalidSignature)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::{keypair_from_seed, PublicKey, SecretKey, KEYPAIR_SEED_SIZE};

    fn test_keypair(seed_byte: u8) -> (PublicKey, SecretKey) {
        keypair_from_seed(&[seed_byte; KEYPAIR_SEED_SIZE]).expect("test keygen")
    }

    #[test]
    fn online_proof_roundtrip() {
        let (pk, sk) = test_keypair(0x11);
        let server_node_id = [0x42u8; 32];
        let nonce = [0x55u8; ONLINE_NONCE_SIZE];
        let proof = ibt_online_proof(&sk, &server_node_id, 1000, &nonce).unwrap();
        let w = ibt_online_verify(&pk, &server_node_id, 1000, &nonce, &proof).unwrap();
        assert_eq!(w, 1000);
    }

    #[test]
    fn online_proof_previous_window_accepted() {
        let (pk, sk) = test_keypair(0x12);
        let server_node_id = [0x42u8; 32];
        let nonce = [0x55u8; ONLINE_NONCE_SIZE];
        // Sign at slot 500 (window 1000 либо 1001 → slot 500)
        let proof = ibt_online_proof(&sk, &server_node_id, 1000, &nonce).unwrap();
        // Verify при current=1002 (slot 501) — ожидание fail так как replay
        // window = current ИЛИ previous (sub 2 windows = 1000, slot 500)
        let w = ibt_online_verify(&pk, &server_node_id, 1002, &nonce, &proof).unwrap();
        assert_eq!(w, 1000);
    }

    #[test]
    fn online_proof_too_old_rejected() {
        let (pk, sk) = test_keypair(0x13);
        let server_node_id = [0x42u8; 32];
        let nonce = [0x55u8; ONLINE_NONCE_SIZE];
        let proof = ibt_online_proof(&sk, &server_node_id, 100, &nonce).unwrap();
        // current = 1000 — slot 500; old slot 50 → reject (вне 2-window window)
        assert_eq!(
            ibt_online_verify(&pk, &server_node_id, 1000, &nonce, &proof),
            Err(IbtError::InvalidSignature)
        );
    }

    #[test]
    fn online_proof_wrong_server_id_rejected() {
        let (pk, sk) = test_keypair(0x14);
        let server_a = [0x42u8; 32];
        let server_b = [0x33u8; 32];
        let nonce = [0x55u8; ONLINE_NONCE_SIZE];
        let proof = ibt_online_proof(&sk, &server_a, 1000, &nonce).unwrap();
        assert_eq!(
            ibt_online_verify(&pk, &server_b, 1000, &nonce, &proof),
            Err(IbtError::InvalidSignature)
        );
    }

    #[test]
    fn online_nonce_replay_rejected() {
        let (pk, sk) = test_keypair(0x15);
        let server_node_id = [0x42u8; 32];
        let nonce = [0x55u8; ONLINE_NONCE_SIZE];
        let proof = ibt_online_proof(&sk, &server_node_id, 1000, &nonce).unwrap();
        let accepted_window =
            ibt_online_verify(&pk, &server_node_id, 1000, &nonce, &proof).unwrap();
        let mut tracker = OnlineNonceTracker::new();
        tracker
            .check_and_insert(&pk, &nonce, 1000, accepted_window)
            .unwrap();
        assert_eq!(
            tracker.check_and_insert(&pk, &nonce, 1000, accepted_window),
            Err(IbtError::ReplayedNonce)
        );
    }

    #[test]
    fn online_nonce_prunes_after_two_window_slots() {
        let (pk, _sk) = test_keypair(0x16);
        let nonce = [0x55u8; ONLINE_NONCE_SIZE];
        let mut tracker = OnlineNonceTracker::new();
        tracker.check_and_insert(&pk, &nonce, 1000, 1000).unwrap();
        assert_eq!(tracker.nonce_count(&pk), 1);
        tracker.check_and_insert(&pk, &nonce, 1004, 1004).unwrap();
        assert_eq!(tracker.nonce_count(&pk), 1);
    }

    #[test]
    fn mesh_proof_roundtrip_within_staleness_window() {
        let (pk, sk) = test_keypair(0x17);
        let peer = [0x33u8; 32];
        let nonce = [0x77u8; 32];
        let cached_w = 5000;
        let known_w = 5000;
        let tau1 = 60;
        let proof = ibt_mesh_proof(&sk, &peer, cached_w, &nonce).unwrap();
        let w = ibt_mesh_verify_with_window(&pk, &peer, known_w, &nonce, &proof, tau1).unwrap();
        // window_slot(5000) == window_slot(5001), so verifier may accept even
        // window
        assert!(w == 5000 || w == 5001);
    }

    #[test]
    fn mesh_proof_outside_staleness_window_rejected() {
        let (pk, sk) = test_keypair(0x18);
        let peer = [0x33u8; 32];
        let nonce = [0x77u8; 32];
        let tau1 = 60;
        let proof = ibt_mesh_proof(&sk, &peer, 1000, &nonce).unwrap();
        // known_window = 1000 + 8·τ₁ — outside 7·τ₁ acceptable bound
        let known_w = 1000 + 8 * tau1;
        assert_eq!(
            ibt_mesh_verify_with_window(&pk, &peer, known_w, &nonce, &proof, tau1),
            Err(IbtError::InvalidSignature)
        );
    }

    #[test]
    fn cross_context_domain_separation() {
        let server = [0x42u8; 32];
        let nonce = [0x77u8; 32];
        let online = ibt_online_message(&server, 1000, &nonce);
        let mesh = ibt_mesh_message(&server, 1000, &nonce);
        assert_ne!(online, mesh, "online vs mesh domain separator must differ");
    }

    #[test]
    fn online_message_byte_layout() {
        let server = [0x42u8; 32];
        let nonce = [0x55u8; ONLINE_NONCE_SIZE];
        let msg = ibt_online_message(&server, 1000, &nonce);
        assert_eq!(msg.len(), TUNNEL_ONLINE.len() + 32 + 8 + ONLINE_NONCE_SIZE);
        assert_eq!(&msg[..TUNNEL_ONLINE.len()], TUNNEL_ONLINE);
        assert_eq!(&msg[TUNNEL_ONLINE.len()..TUNNEL_ONLINE.len() + 32], &server);
        assert_eq!(
            &msg[TUNNEL_ONLINE.len() + 32..TUNNEL_ONLINE.len() + 40],
            &500u64.to_le_bytes()
        );
        assert_eq!(&msg[TUNNEL_ONLINE.len() + 40..], &nonce);
    }

    #[test]
    fn mesh_message_byte_layout() {
        let peer = [0x33u8; 32];
        let nonce = [0x77u8; 32];
        let msg = ibt_mesh_message(&peer, 5000, &nonce);
        let exp_len = DOMAIN_TUNNEL_MESH.len() + 32 + 8 + 32;
        assert_eq!(msg.len(), exp_len);
        assert_eq!(&msg[..TUNNEL_MESH.len()], TUNNEL_MESH);
        let off = TUNNEL_MESH.len();
        assert_eq!(&msg[off..off + 32], &peer);
        assert_eq!(&msg[off + 32..off + 40], &2500u64.to_le_bytes());
        assert_eq!(&msg[off + 40..], &nonce);
    }
}
