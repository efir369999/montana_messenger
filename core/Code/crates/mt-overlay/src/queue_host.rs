//! Host-store MUQ (Stage 2): queue table (recv_id→Queue, send_id→recv_id) + shard buffer,
//! two-hop deposit, fetch. Off-chain ([P2P-1]). The TTL/drop mechanics
//! inherit the Stage 2 store, buffer key = recv_id.

use std::collections::{HashMap, HashSet};

use mt_crypto::Signature;

use crate::challenge::ChannelHash;
use crate::frame::{MsgId, MAX_PAYLOAD_LEN};
use crate::muq::{
    verify_deposit, verify_subscribe, HostDeposit, Queue, QueueId, QueueItem, RELAY_CHANNEL_MARKER,
};

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct StoredShard {
    pub msg_id: MsgId,
    pub shard_index: u8,
    pub shard_total: u8,
    pub ct: Vec<u8>,
    pub expire_window: u64,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum DepositError {
    NoQueue,      // send_id matches no queue
    Unauthorized, // secured queue, the send_key signature failed
    QuotaFull,    // the queue buffer reached its quota
    OversizeShard,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SubscribeError {
    NoQueue,
    BadSig, // the fetch signature failed (recv_pubkey / channel_hash)
    Replay, // two-hop fetch: nonce already used (a stolen QueueSubscribe is not portable)
}

/// DEV-050(a) [I-15]: global limit of queue registrations per window (~60s) — time-based
/// anti-fan-out (no money). recv_id is anonymous (not an identity), so the ceiling is global
/// per host node per window; mass multiplication of queues is slowed by time.
pub const MAX_REGISTRATIONS_PER_WINDOW: u32 = 1024;
/// DEV-050(c): ceiling of unconsumed host-issued nonces per recv_id — a memory bound against
/// issue-without-subscribe flooding. On overflow the old ones are reset (a re-request is legitimate).
pub const MAX_ISSUED_NONCES: usize = 64;

#[derive(Default)]
pub struct QueueHost {
    queues: HashMap<QueueId, Queue>,            // recv_id → Queue
    send_route: HashMap<QueueId, QueueId>,      // send_id → recv_id
    buffer: HashMap<QueueId, Vec<StoredShard>>, // recv_id → shards
    issued_nonces: HashMap<QueueId, HashSet<crate::challenge::Nonce>>, // DEV-050(c) §478: nonces issued by the host (host-issued, one-time)
    reg_window: u64, // DEV-050(a): current window of the registration counter
    reg_count: u32,  // DEV-050(a): registrations in reg_window
}

impl QueueHost {
    pub fn new() -> Self {
        Self::default()
    }

    /// DEV-050(c) §478: the host issues a fresh nonce for a fetch (before QueueSubscribe).
    /// One-time — consumed at subscribe_relay. Replaces client-generated nonce +
    /// volatile-dedup: a stolen QueueSubscribe is not portable (the nonce was not issued for this request).
    pub fn issue_nonce(&mut self, recv_id: &QueueId) -> crate::challenge::Nonce {
        let mut nonce = [0u8; crate::challenge::NONCE_SIZE];
        getrandom::getrandom(&mut nonce).expect("OS CSPRNG");
        let set = self.issued_nonces.entry(*recv_id).or_default();
        if set.len() >= MAX_ISSUED_NONCES {
            set.clear(); // memory bound (issue flood without subscribe)
        }
        set.insert(nonce);
        nonce
    }

    /// The host creates a queue (recv_id/send_id are independent; the recipient sent recv_pubkey).
    /// Any registered send_id (self-host: one queue) — for the hello capability exchange.
    pub fn any_send_id(&self) -> Option<QueueId> {
        self.send_route.keys().next().copied()
    }

    pub fn register_queue(&mut self, q: Queue, current_window: u64) -> bool {
        // DEV-050(a) [I-15]: global registration rate-limit per window (anti-fan-out).
        if current_window != self.reg_window {
            self.reg_window = current_window;
            self.reg_count = 0;
        }
        if self.reg_count >= MAX_REGISTRATIONS_PER_WINDOW {
            return false; // window limit exhausted — registration rejected
        }
        // DEV-050(d): first-write-wins — an existing recv_id is not overwritten with another
        // recv_pubkey. Otherwise a party that learned recv_id (a log / a compromised
        // recipient) would re-register the queue to its own recv_pubkey and intercept the
        // drain. Re-key by the owner (signature of the prior key) is a separate future opcode; hijack
        // is closed by forbidding silent overwrite.
        if let Some(existing) = self.queues.get(&q.recv_id) {
            if existing.recv_pubkey != q.recv_pubkey {
                return false;
            }
        }
        self.reg_count += 1;
        self.send_route.insert(q.send_id, q.recv_id);
        self.queues.insert(q.recv_id, q);
        true
    }

    /// Two-hop deposit: the proxy brought an unwrapped HostDeposit. The send_id→recv_id route
    /// is held only by the host (unlinkability). secured → verify send_key.
    pub fn deposit(&mut self, hd: &HostDeposit, current_window: u64) -> Result<(), DepositError> {
        let recv_id = *self
            .send_route
            .get(&hd.send_id)
            .ok_or(DepositError::NoQueue)?;
        let q = self.queues.get(&recv_id).ok_or(DepositError::NoQueue)?;
        if let Some(send_pubkey) = &q.send_pubkey {
            let sig = Signature::from_slice(&hd.sig).ok_or(DepositError::Unauthorized)?;
            if !verify_deposit(send_pubkey, &hd.send_id, &hd.msg_id, &hd.nonce, &sig) {
                return Err(DepositError::Unauthorized);
            }
        }
        if hd.ct.len() > MAX_PAYLOAD_LEN {
            return Err(DepositError::OversizeShard);
        }
        let buf = self.buffer.entry(recv_id).or_default();
        if buf.len() as u32 >= q.quota {
            return Err(DepositError::QuotaFull);
        }
        buf.push(StoredShard {
            msg_id: hd.msg_id,
            shard_index: hd.shard_index,
            shard_total: hd.shard_total,
            ct: hd.ct.clone(),
            expire_window: current_window.saturating_add(hd.ttl_windows as u64),
        });
        Ok(())
    }

    /// Fetch: recv_key signature against the STORED recv_pubkey + channel_hash (E-2/F3).
    /// Returns a slice of shards (no clone).
    pub fn subscribe(
        &self,
        recv_id: &QueueId,
        nonce: &crate::challenge::Nonce,
        channel_hash: &ChannelHash,
        sig: &Signature,
    ) -> Result<&[StoredShard], SubscribeError> {
        let q = self.queues.get(recv_id).ok_or(SubscribeError::NoQueue)?;
        if !verify_subscribe(&q.recv_pubkey, recv_id, nonce, channel_hash, sig) {
            return Err(SubscribeError::BadSig);
        }
        Ok(self.buffer.get(recv_id).map(Vec::as_slice).unwrap_or(&[]))
    }

    /// Two-hop fetch through a courier: channel_hash is absent (no direct B<->host channel),
    /// so the signature is verified with RELAY_CHANNEL_MARKER (0×32), and anti-replay is carried by
    /// nonce-tracking per recv_id — a stolen QueueSubscribe is not portable (the nonce is one-time).
    /// Returns a copy of the shards (not a borrow; the caller drops the delivered ones separately).
    pub fn subscribe_relay(
        &mut self,
        recv_id: &QueueId,
        nonce: &crate::challenge::Nonce,
        sig: &Signature,
    ) -> Result<Vec<QueueItem>, SubscribeError> {
        let recv_pubkey = self
            .queues
            .get(recv_id)
            .ok_or(SubscribeError::NoQueue)?
            .recv_pubkey;
        if !verify_subscribe(&recv_pubkey, recv_id, nonce, &RELAY_CHANNEL_MARKER, sig) {
            return Err(SubscribeError::BadSig);
        }
        // DEV-050(c) §478: the nonce must be ISSUED by the host (issue_nonce) and is consumed
        // one-time — a stolen/replayed QueueSubscribe with a non-issued nonce is rejected.
        let issued = self
            .issued_nonces
            .get_mut(recv_id)
            .map(|set| set.remove(nonce))
            .unwrap_or(false);
        if !issued {
            return Err(SubscribeError::Replay);
        }
        Ok(self.buffer_of(recv_id))
    }

    /// DEV-049(a) §593: the recipient confirmed receipt — the host deletes the queue buffer. Drop
    /// ONLY on confirmation by B (not on hand-off to a courier). Authenticated like a fetch:
    /// recv_key signature over the host-issued nonce — a stolen/forged ack (recv_id alone)
    /// does not drop someone else's buffer.
    pub fn ack_drain(
        &mut self,
        recv_id: &QueueId,
        nonce: &crate::challenge::Nonce,
        sig: &Signature,
    ) -> bool {
        let recv_pubkey = match self.queues.get(recv_id) {
            Some(q) => q.recv_pubkey,
            None => return false,
        };
        if !verify_subscribe(&recv_pubkey, recv_id, nonce, &RELAY_CHANNEL_MARKER, sig) {
            return false;
        }
        let issued = self
            .issued_nonces
            .get_mut(recv_id)
            .map(|set| set.remove(nonce))
            .unwrap_or(false);
        if !issued {
            return false;
        }
        self.buffer.remove(recv_id);
        true
    }

    pub fn drop_delivered(&mut self, recv_id: &QueueId, msg_id: &MsgId) {
        if let Some(v) = self.buffer.get_mut(recv_id) {
            v.retain(|s| &s.msg_id != msg_id);
        }
    }

    pub fn prune(&mut self, current_window: u64) {
        for v in self.buffer.values_mut() {
            v.retain(|s| s.expire_window >= current_window);
        }
        self.buffer.retain(|_, v| !v.is_empty());
    }

    pub fn buffer_of(&self, recv_id: &QueueId) -> Vec<QueueItem> {
        self.buffer
            .get(recv_id)
            .map(|v| {
                v.iter()
                    .map(|s| QueueItem {
                        msg_id: s.msg_id,
                        shard_index: s.shard_index,
                        shard_total: s.shard_total,
                        ct: s.ct.clone(),
                    })
                    .collect()
            })
            .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::muq::sign_deposit;
    use mt_crypto::{keypair_from_seed, PublicKey, SecretKey, PUBLIC_KEY_SIZE};

    fn kp(seed: u8) -> ([u8; PUBLIC_KEY_SIZE], SecretKey) {
        let (pk, sk): (PublicKey, SecretKey) = keypair_from_seed(&[seed; 32]).unwrap();
        (*pk.as_bytes(), sk)
    }

    #[test]
    fn register_queue_first_write_wins_rejects_hijack() {
        let (rpk, _) = kp(0x51);
        let (hijacker_pk, _) = kp(0x52);
        let mut host = QueueHost::new();
        let q = Queue {
            recv_id: [0x71; 32],
            send_id: [0x81; 32],
            recv_pubkey: rpk,
            send_pubkey: None,
            rotation_epoch: 0,
            quota: 8,
        };
        assert!(host.register_queue(q.clone(), 0)); // first registration accepted
        assert!(host.register_queue(q.clone(), 0)); // same recv_pubkey — idempotently ok
        let mut hijack = q.clone();
        hijack.recv_pubkey = hijacker_pk;
        assert!(!host.register_queue(hijack, 0)); // DEV-050(d): hijack rejected (first-write-wins)
    }

    #[test]
    fn relay_subscribe_nonce_replay_rejected() {
        use crate::muq::sign_subscribe_relay;
        let (rpk, rsk) = kp(0x11);
        let mut host = QueueHost::new();
        host.register_queue(
            Queue {
                recv_id: [0x71; 32],
                send_id: [0x51; 32],
                recv_pubkey: rpk,
                send_pubkey: None,
                rotation_epoch: 1000,
                quota: 64,
            },
            0,
        );
        let recv_id = [0x71u8; 32];
        // DEV-050(c) §478: the nonce is issued by the host (host-issued), not by the client
        let nonce = host.issue_nonce(&recv_id);
        let sig = sign_subscribe_relay(&rsk, &recv_id, &nonce).unwrap();
        // first fetch — ok (the nonce was issued by the host, consumed one-time)
        assert!(host.subscribe_relay(&recv_id, &nonce, &sig).is_ok());
        // repeat of the SAME nonce — Replay (host-issued nonce is one-time, already consumed)
        assert_eq!(
            host.subscribe_relay(&recv_id, &nonce, &sig),
            Err(SubscribeError::Replay)
        );
        // a nonce not issued by the host is rejected (stolen/fabricated is not portable)
        let forged = [0x99u8; 16];
        let fsig = sign_subscribe_relay(&rsk, &recv_id, &forged).unwrap();
        assert_eq!(
            host.subscribe_relay(&recv_id, &forged, &fsig),
            Err(SubscribeError::Replay)
        );
    }

    #[test]
    fn deposit_via_route_then_subscribe() {
        let (rpk, _rsk) = kp(0x11);
        let (spk, ssk) = kp(0x22);
        let mut host = QueueHost::new();
        let q = Queue {
            recv_id: [0x71; 32],
            send_id: [0x51; 32],
            recv_pubkey: rpk,
            send_pubkey: Some(spk),
            rotation_epoch: 1000,
            quota: 64,
        };
        host.register_queue(q, 0);

        let nonce = [0x07; 16];
        let sig = sign_deposit(&ssk, &[0x51; 32], &[0x5A; 16], &nonce).unwrap();
        let hd = HostDeposit {
            send_id: [0x51; 32],
            msg_id: [0x5A; 16],
            ttl_windows: 240,
            shard_index: 0,
            shard_total: 1,
            nonce,
            ct: vec![0xCC; 64],
            sig: *sig.as_bytes(),
        };
        host.deposit(&hd, 100).unwrap();
        assert_eq!(host.buffer_of(&[0x71; 32]).len(), 1);
    }

    #[test]
    fn foreign_send_id_no_queue() {
        let mut host = QueueHost::new();
        let hd = HostDeposit {
            send_id: [0x99; 32],
            msg_id: [1; 16],
            ttl_windows: 1,
            shard_index: 0,
            shard_total: 1,
            nonce: [0; 16],
            ct: vec![1; 8],
            sig: [0u8; mt_crypto::SIGNATURE_SIZE],
        };
        assert_eq!(host.deposit(&hd, 100), Err(DepositError::NoQueue));
    }

    #[test]
    fn unauthorized_deposit_rejected() {
        let (rpk, _) = kp(0x11);
        let (spk, _ssk) = kp(0x22);
        let (_epk, esk) = kp(0x33); // an outsider
        let mut host = QueueHost::new();
        host.register_queue(
            Queue {
                recv_id: [0x71; 32],
                send_id: [0x51; 32],
                recv_pubkey: rpk,
                send_pubkey: Some(spk),
                rotation_epoch: 1000,
                quota: 64,
            },
            0,
        );
        let nonce = [0x07; 16];
        let bad = sign_deposit(&esk, &[0x51; 32], &[0x5A; 16], &nonce).unwrap();
        let hd = HostDeposit {
            send_id: [0x51; 32],
            msg_id: [0x5A; 16],
            ttl_windows: 1,
            shard_index: 0,
            shard_total: 1,
            nonce,
            ct: vec![1; 8],
            sig: *bad.as_bytes(),
        };
        assert_eq!(host.deposit(&hd, 100), Err(DepositError::Unauthorized));
    }

    #[test]
    fn quota_and_ttl() {
        let (rpk, _) = kp(0x11);
        let mut host = QueueHost::new();
        host.register_queue(
            Queue {
                recv_id: [0x71; 32],
                send_id: [0x51; 32],
                recv_pubkey: rpk,
                send_pubkey: None,
                rotation_epoch: 1000,
                quota: 2,
            },
            0,
        );
        for i in 0..2u8 {
            let hd = HostDeposit {
                send_id: [0x51; 32],
                msg_id: [i; 16],
                ttl_windows: 10,
                shard_index: 0,
                shard_total: 1,
                nonce: [0; 16],
                ct: vec![i; 8],
                sig: [0u8; mt_crypto::SIGNATURE_SIZE],
            };
            host.deposit(&hd, 100).unwrap();
        }
        let over = HostDeposit {
            send_id: [0x51; 32],
            msg_id: [9; 16],
            ttl_windows: 10,
            shard_index: 0,
            shard_total: 1,
            nonce: [0; 16],
            ct: vec![9; 8],
            sig: [0u8; mt_crypto::SIGNATURE_SIZE],
        };
        assert_eq!(host.deposit(&over, 100), Err(DepositError::QuotaFull));
        host.prune(111);
        assert_eq!(host.buffer_of(&[0x71; 32]).len(), 0);
    }
}
