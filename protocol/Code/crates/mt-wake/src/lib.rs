//! Stage 7 — Wake ladder (P2P Network spec). Byte-exact wake formats:
//! WakeInline (rungs 1–3, Apple outside the loop) / WakeHandle (rung 4, APNs/FCM),
//! the account_id↔wake_handle registry at the postman (R5), the rung arbiter. The formats
//! never carry content or the sender.

use std::collections::BTreeMap;

use mt_crypto::HASH_SIZE;
use thiserror::Error;

/// Queue recv_id (Stage 2, mt-postman QueueId) — 32 B. Numerically = HASH_SIZE;
/// semantically = QueueId (a random id, not a hash). SSOT drift is caught by the dev test below.
pub const RECV_ID_LEN: usize = HASH_SIZE;
/// account_id — public identity identifier (SSOT mt-state::derive_account_id) — 32 B.
pub const ACCOUNT_ID_LEN: usize = HASH_SIZE;
/// Opaque rung-4 wake descriptor — unlinkable to recv_id (R5).
pub const WAKE_HANDLE_LEN: usize = 16;
/// WakeInline wire size: recv_id 32 + window 8.
pub const WAKE_INLINE_LEN: usize = RECV_ID_LEN + 8;
/// WakeHandle wire size: wake_handle 16 + window 8.
pub const WAKE_HANDLE_MSG_LEN: usize = WAKE_HANDLE_LEN + 8;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum WakeError {
    #[error("truncated: expected {expected}, got {got}")]
    Truncated { expected: usize, got: usize },
    #[error("trailing bytes: {0}")]
    TrailingBytes(usize),
    #[error("csprng failure")]
    Csprng,
}

fn check_len(got: usize, expected: usize) -> Result<(), WakeError> {
    match got.cmp(&expected) {
        std::cmp::Ordering::Less => Err(WakeError::Truncated { expected, got }),
        std::cmp::Ordering::Greater => Err(WakeError::TrailingBytes(got - expected)),
        std::cmp::Ordering::Equal => Ok(()),
    }
}

/// Rung 1–3 wake: postman → recipient directly (Apple outside the loop),
/// the queue address is open to the recipient (not to Apple).
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct WakeInline {
    pub recv_id: [u8; RECV_ID_LEN],
    pub window: u64,
}

impl WakeInline {
    pub fn encode(&self) -> [u8; WAKE_INLINE_LEN] {
        let mut out = [0u8; WAKE_INLINE_LEN];
        out[..RECV_ID_LEN].copy_from_slice(&self.recv_id);
        out[RECV_ID_LEN..].copy_from_slice(&self.window.to_le_bytes());
        out
    }

    pub fn decode(input: &[u8]) -> Result<Self, WakeError> {
        check_len(input.len(), WAKE_INLINE_LEN)?;
        let mut recv_id = [0u8; RECV_ID_LEN];
        recv_id.copy_from_slice(&input[..RECV_ID_LEN]);
        let window = u64::from_le_bytes(input[RECV_ID_LEN..WAKE_INLINE_LEN].try_into().unwrap());
        Ok(Self { recv_id, window })
    }
}

/// Rung 4 wake: push gateway → APNs/FCM. The gateway and Apple see ONLY wake_handle
/// (not recv_id) — decoupling from the queue address (§11).
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct WakeHandle {
    pub wake_handle: [u8; WAKE_HANDLE_LEN],
    pub window: u64,
}

impl WakeHandle {
    pub fn encode(&self) -> [u8; WAKE_HANDLE_MSG_LEN] {
        let mut out = [0u8; WAKE_HANDLE_MSG_LEN];
        out[..WAKE_HANDLE_LEN].copy_from_slice(&self.wake_handle);
        out[WAKE_HANDLE_LEN..].copy_from_slice(&self.window.to_le_bytes());
        out
    }

    pub fn decode(input: &[u8]) -> Result<Self, WakeError> {
        check_len(input.len(), WAKE_HANDLE_MSG_LEN)?;
        let mut wake_handle = [0u8; WAKE_HANDLE_LEN];
        wake_handle.copy_from_slice(&input[..WAKE_HANDLE_LEN]);
        let window = u64::from_le_bytes(
            input[WAKE_HANDLE_LEN..WAKE_HANDLE_MSG_LEN]
                .try_into()
                .unwrap(),
        );
        Ok(Self {
            wake_handle,
            window,
        })
    }
}

/// The account_id↔wake_handle registry at the postman (R5). The postman knows the account_id of its
/// user; the gateway holds only wake_handle↔device_token and sees neither account_id nor recv_id.
/// wake_handle is generated from the OS CSPRNG — unlinkable to recv_id by construction.
#[derive(Default)]
pub struct WakeRegistry {
    forward: BTreeMap<[u8; ACCOUNT_ID_LEN], [u8; WAKE_HANDLE_LEN]>,
    reverse: BTreeMap<[u8; WAKE_HANDLE_LEN], [u8; ACCOUNT_ID_LEN]>,
}

impl WakeRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Idempotent registration: a repeat for the same account_id returns the existing
    /// handle (creates no new records). A new handle is 16 B of OS CSPRNG, collision excluded.
    pub fn register(
        &mut self,
        account_id: [u8; ACCOUNT_ID_LEN],
    ) -> Result<[u8; WAKE_HANDLE_LEN], WakeError> {
        if let Some(h) = self.forward.get(&account_id) {
            return Ok(*h);
        }
        let mut handle = [0u8; WAKE_HANDLE_LEN];
        loop {
            getrandom::getrandom(&mut handle).map_err(|_| WakeError::Csprng)?;
            if !self.reverse.contains_key(&handle) {
                break;
            }
        }
        self.forward.insert(account_id, handle);
        self.reverse.insert(handle, account_id);
        Ok(handle)
    }

    pub fn handle_of(&self, account_id: &[u8; ACCOUNT_ID_LEN]) -> Option<[u8; WAKE_HANDLE_LEN]> {
        self.forward.get(account_id).copied()
    }

    /// The postman resolves handle→account_id on a rung-4 wake (asks its own
    /// registry which recv_id are waiting for this account_id).
    pub fn account_of(&self, handle: &[u8; WAKE_HANDLE_LEN]) -> Option<[u8; ACCOUNT_ID_LEN]> {
        self.reverse.get(handle).copied()
    }

    pub fn len(&self) -> usize {
        self.forward.len()
    }

    pub fn is_empty(&self) -> bool {
        self.forward.is_empty()
    }
}

/// The four wake rungs (§10), in descending sovereignty. Number = priority
/// (lower — higher sovereignty; Apple is only rung 4).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum WakeRung {
    LiveTunnel = 1,
    IBeaconHome = 2,
    UnlockSync = 3,
    PushGateway = 4,
}

impl WakeRung {
    /// Rungs 1–3 carry WakeInline (Apple outside the loop); rung 4 carries WakeHandle.
    pub fn carries_inline(&self) -> bool {
        !matches!(self, WakeRung::PushGateway)
    }
}

/// Rung arbiter: the highest available first (1–3 are free and sovereign; APNs/FCM only
/// when none of 1–3 worked). Rung 4 is the guarantee layer, always available.
pub fn select_rung(live_tunnel: bool, ibeacon_home: bool, unlock_sync: bool) -> WakeRung {
    if live_tunnel {
        WakeRung::LiveTunnel
    } else if ibeacon_home {
        WakeRung::IBeaconHome
    } else if unlock_sync {
        WakeRung::UnlockSync
    } else {
        WakeRung::PushGateway
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recv_id_len_matches_canonical_queue_id() {
        // SSOT: RECV_ID_LEN is semantically = QueueId (Stage 2). mt-wake is crypto-only (does not
        // depend on mt-overlay in production), so drift is caught by a dev test, not by `use`.
        assert_eq!(RECV_ID_LEN, mt_overlay::muq::QUEUE_ID_SIZE);
    }

    #[test]
    fn wake_inline_kat() {
        let mut recv_id = [0u8; RECV_ID_LEN];
        for (i, b) in recv_id.iter_mut().enumerate() {
            *b = i as u8;
        }
        let w = WakeInline { recv_id, window: 1 };
        let enc = w.encode();
        assert_eq!(enc.len(), WAKE_INLINE_LEN);
        let expect =
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f0100000000000000";
        assert_eq!(hex::encode(enc), expect);
        assert_eq!(WakeInline::decode(&enc).unwrap(), w);
    }

    #[test]
    fn wake_handle_kat() {
        let w = WakeHandle {
            wake_handle: [0xaa; WAKE_HANDLE_LEN],
            window: 0x0102,
        };
        let enc = w.encode();
        assert_eq!(enc.len(), WAKE_HANDLE_MSG_LEN);
        let expect = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0201000000000000";
        assert_eq!(hex::encode(enc), expect);
        assert_eq!(WakeHandle::decode(&enc).unwrap(), w);
    }

    #[test]
    fn decode_truncated() {
        assert_eq!(
            WakeInline::decode(&[0u8; 39]),
            Err(WakeError::Truncated {
                expected: 40,
                got: 39
            })
        );
        assert_eq!(
            WakeHandle::decode(&[0u8; 23]),
            Err(WakeError::Truncated {
                expected: 24,
                got: 23
            })
        );
    }

    #[test]
    fn decode_trailing() {
        assert_eq!(
            WakeInline::decode(&[0u8; 41]),
            Err(WakeError::TrailingBytes(1))
        );
        assert_eq!(
            WakeHandle::decode(&[0u8; 25]),
            Err(WakeError::TrailingBytes(1))
        );
    }

    #[test]
    fn registry_idempotent_and_bijective() {
        let mut reg = WakeRegistry::new();
        let acc = [7u8; ACCOUNT_ID_LEN];
        let h1 = reg.register(acc).unwrap();
        let h2 = reg.register(acc).unwrap();
        assert_eq!(h1, h2);
        assert_eq!(reg.len(), 1);
        assert_eq!(reg.handle_of(&acc), Some(h1));
        assert_eq!(reg.account_of(&h1), Some(acc));
        let acc2 = [9u8; ACCOUNT_ID_LEN];
        let h3 = reg.register(acc2).unwrap();
        assert_ne!(h1, h3);
        assert_eq!(reg.len(), 2);
    }

    #[test]
    fn handle_not_derived_from_account() {
        let mut reg = WakeRegistry::new();
        let acc = [0xABu8; ACCOUNT_ID_LEN];
        let h = reg.register(acc).unwrap();
        assert_ne!(&h[..], &acc[..WAKE_HANDLE_LEN]);
    }

    #[test]
    fn arbiter_priority() {
        assert_eq!(select_rung(true, true, true), WakeRung::LiveTunnel);
        assert_eq!(select_rung(false, true, true), WakeRung::IBeaconHome);
        assert_eq!(select_rung(false, false, true), WakeRung::UnlockSync);
        assert_eq!(select_rung(false, false, false), WakeRung::PushGateway);
    }

    #[test]
    fn rung_format_binding() {
        assert!(WakeRung::LiveTunnel.carries_inline());
        assert!(WakeRung::IBeaconHome.carries_inline());
        assert!(WakeRung::UnlockSync.carries_inline());
        assert!(!WakeRung::PushGateway.carries_inline());
    }
}
