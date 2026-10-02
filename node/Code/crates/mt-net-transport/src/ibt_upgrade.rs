// IBT proof exchange как custom protocol upgrade поверх Noise.
//
// Spec section "Connection lifecycle" Step 4-5:
//   После Noise key agreement клиент отправляет IBT proof,
//   сервер verify + access level determination
//   (node / candidate / account) per Identity-Bound Tunnel.

use mt_crypto::PublicKey;
use mt_net::ibt::{ibt_online_verify, IbtError, OnlineNonceTracker, ONLINE_NONCE_SIZE};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IbtAccessLevel {
    Node,
    Candidate,
    Account,
}

#[derive(Debug, Clone)]
pub struct IbtConfig {
    pub server_node_id: [u8; 32],
    pub current_window: u64,
}

pub fn classify_proof(
    config: &IbtConfig,
    client_pk: &PublicKey,
    online_session_nonce: &[u8; ONLINE_NONCE_SIZE],
    proof: &mt_crypto::Signature,
    nonce_tracker: &mut OnlineNonceTracker,
    lookup_level: Option<IbtAccessLevel>,
) -> Result<IbtAccessLevel, IbtError> {
    let accepted_window = ibt_online_verify(
        client_pk,
        &config.server_node_id,
        config.current_window,
        online_session_nonce,
        proof,
    )?;
    let level = lookup_level.ok_or(IbtError::InvalidSignature)?;
    nonce_tracker.check_and_insert(
        client_pk,
        online_session_nonce,
        config.current_window,
        accepted_window,
    )?;
    Ok(level)
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::{keypair_from_seed, PublicKey, SecretKey, KEYPAIR_SEED_SIZE};
    use mt_net::ibt::ibt_online_proof;

    fn test_keypair(seed_byte: u8) -> (PublicKey, SecretKey) {
        keypair_from_seed(&[seed_byte; KEYPAIR_SEED_SIZE]).expect("test keygen")
    }

    #[test]
    fn classify_node_level() {
        let (pk, sk) = test_keypair(0x21);
        let config = IbtConfig {
            server_node_id: [0x42; 32],
            current_window: 1000,
        };
        let nonce = [0x55; ONLINE_NONCE_SIZE];
        let proof = ibt_online_proof(&sk, &config.server_node_id, 1000, &nonce).unwrap();
        let mut tracker = OnlineNonceTracker::new();
        let level = classify_proof(
            &config,
            &pk,
            &nonce,
            &proof,
            &mut tracker,
            Some(IbtAccessLevel::Node),
        )
        .unwrap();
        assert_eq!(level, IbtAccessLevel::Node);
    }

    #[test]
    fn classify_candidate_level() {
        let (pk, sk) = test_keypair(0x22);
        let config = IbtConfig {
            server_node_id: [0x42; 32],
            current_window: 1000,
        };
        let nonce = [0x56; ONLINE_NONCE_SIZE];
        let proof = ibt_online_proof(&sk, &config.server_node_id, 1000, &nonce).unwrap();
        let mut tracker = OnlineNonceTracker::new();
        let level = classify_proof(
            &config,
            &pk,
            &nonce,
            &proof,
            &mut tracker,
            Some(IbtAccessLevel::Candidate),
        )
        .unwrap();
        assert_eq!(level, IbtAccessLevel::Candidate);
    }

    #[test]
    fn classify_account_level() {
        let (pk, sk) = test_keypair(0x23);
        let config = IbtConfig {
            server_node_id: [0x42; 32],
            current_window: 1000,
        };
        let nonce = [0x57; ONLINE_NONCE_SIZE];
        let proof = ibt_online_proof(&sk, &config.server_node_id, 1000, &nonce).unwrap();
        let mut tracker = OnlineNonceTracker::new();
        let level = classify_proof(
            &config,
            &pk,
            &nonce,
            &proof,
            &mut tracker,
            Some(IbtAccessLevel::Account),
        )
        .unwrap();
        assert_eq!(level, IbtAccessLevel::Account);
    }

    #[test]
    fn classify_unknown_rejected() {
        let (pk, sk) = test_keypair(0x24);
        let config = IbtConfig {
            server_node_id: [0x42; 32],
            current_window: 1000,
        };
        let nonce = [0x58; ONLINE_NONCE_SIZE];
        let proof = ibt_online_proof(&sk, &config.server_node_id, 1000, &nonce).unwrap();
        let mut tracker = OnlineNonceTracker::new();
        let r = classify_proof(&config, &pk, &nonce, &proof, &mut tracker, None);
        assert_eq!(r, Err(IbtError::InvalidSignature));
    }

    #[test]
    fn classify_invalid_proof_rejected() {
        let (pk, _sk) = test_keypair(0x25);
        let (_pk2, sk2) = test_keypair(0x26);
        let config = IbtConfig {
            server_node_id: [0x42; 32],
            current_window: 1000,
        };
        // proof signed by sk2, classified против pk → fail
        let nonce = [0x59; ONLINE_NONCE_SIZE];
        let proof = ibt_online_proof(&sk2, &config.server_node_id, 1000, &nonce).unwrap();
        let mut tracker = OnlineNonceTracker::new();
        let r = classify_proof(
            &config,
            &pk,
            &nonce,
            &proof,
            &mut tracker,
            Some(IbtAccessLevel::Node),
        );
        assert_eq!(r, Err(IbtError::InvalidSignature));
    }

    #[test]
    fn classify_replayed_nonce_rejected() {
        let (pk, sk) = test_keypair(0x27);
        let config = IbtConfig {
            server_node_id: [0x42; 32],
            current_window: 1000,
        };
        let nonce = [0x5A; ONLINE_NONCE_SIZE];
        let proof = ibt_online_proof(&sk, &config.server_node_id, 1000, &nonce).unwrap();
        let mut tracker = OnlineNonceTracker::new();
        classify_proof(
            &config,
            &pk,
            &nonce,
            &proof,
            &mut tracker,
            Some(IbtAccessLevel::Node),
        )
        .unwrap();
        let replay = classify_proof(
            &config,
            &pk,
            &nonce,
            &proof,
            &mut tracker,
            Some(IbtAccessLevel::Node),
        );
        assert_eq!(replay, Err(IbtError::ReplayedNonce));
    }
}
