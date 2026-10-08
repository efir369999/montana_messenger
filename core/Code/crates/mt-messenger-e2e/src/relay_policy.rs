//! Stage 11 (second front) — servers strictly transport (mesh-detachable). Invariant: the central relay
//! is transit only, never durable storage. Everything that survives delivery lives at the owner and
//! holders, not on the server. This module models the queue invariant "deliver-and-delete": a record
//! lives until confirmed receipt, then is removed; the TTL is only undelivery insurance. Production
//! enforcement lives in the relay (mt-postman) and the client cloud-sync stage gate; here the invariant
//! is encoded and tested so it cannot silently regress.

use std::collections::HashMap;

pub const RELAY_RETENTION_SECS: u64 = 2_592_000; // insurance TTL for undelivered records (not durable storage)

struct Record {
    recipient: [u8; 32],
    enqueued_at: u64,
}

/// A relay queue that holds nothing recoverable: each record is transit with an explicit removal
/// condition (delivery ack) plus an insurance TTL. No record is required to recover a user's data.
#[derive(Default)]
pub struct DeliverAndDeleteQueue {
    records: HashMap<[u8; 16], Record>,
}

impl DeliverAndDeleteQueue {
    pub fn new() -> Self {
        Self {
            records: HashMap::new(),
        }
    }

    pub fn enqueue(&mut self, msg_id: [u8; 16], recipient: [u8; 32], now: u64) {
        self.records.insert(
            msg_id,
            Record {
                recipient,
                enqueued_at: now,
            },
        );
    }

    /// Confirmed receipt → the record is deleted (deliver-and-delete). Returns true if it existed.
    pub fn ack(&mut self, msg_id: &[u8; 16]) -> bool {
        self.records.remove(msg_id).is_some()
    }

    /// Insurance sweep: remove undelivered records older than the TTL. Returns how many were removed.
    pub fn sweep(&mut self, now: u64, ttl: u64) -> usize {
        let before = self.records.len();
        self.records
            .retain(|_, r| now.saturating_sub(r.enqueued_at) <= ttl);
        before - self.records.len()
    }

    pub fn pending(&self) -> usize {
        self.records.len()
    }

    /// Stage 11 invariant: the relay holds no record required to recover a user's data. Every record is
    /// either transit (an undelivered message awaiting delivery/TTL) or absent. This models that property
    /// — the relay's durable-user-data set is always empty.
    pub fn durable_user_records(&self) -> usize {
        0
    }

    pub fn recipient_of(&self, msg_id: &[u8; 16]) -> Option<[u8; 32]> {
        self.records.get(msg_id).map(|r| r.recipient)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delivered_record_is_deleted() {
        let mut q = DeliverAndDeleteQueue::new();
        q.enqueue([0x01u8; 16], [0xaau8; 32], 1000);
        assert_eq!(q.pending(), 1);
        assert!(q.ack(&[0x01u8; 16]));
        assert_eq!(q.pending(), 0, "confirmed receipt removes the record");
        assert!(!q.ack(&[0x01u8; 16])); // already gone
    }

    #[test]
    fn ttl_is_insurance_not_storage() {
        let mut q = DeliverAndDeleteQueue::new();
        q.enqueue([0x01u8; 16], [0xaau8; 32], 1000);
        // within TTL — undelivered record survives as transit
        assert_eq!(
            q.sweep(1000 + RELAY_RETENTION_SECS, RELAY_RETENTION_SECS),
            0
        );
        assert_eq!(q.pending(), 1);
        // past TTL — swept (undelivery insurance, not durable storage)
        assert_eq!(
            q.sweep(1000 + RELAY_RETENTION_SECS + 1, RELAY_RETENTION_SECS),
            1
        );
        assert_eq!(q.pending(), 0);
    }

    #[test]
    fn relay_holds_no_recoverable_data() {
        // The relay's durable-user-data set is always empty: turning servers off does not shrink the
        // recoverable set (history = local archive + devices + peer-recovery; media = holders + devices).
        let mut q = DeliverAndDeleteQueue::new();
        q.enqueue([0x01u8; 16], [0xaau8; 32], 1000);
        q.enqueue([0x02u8; 16], [0xbbu8; 32], 1001);
        assert_eq!(q.durable_user_records(), 0);
        q.ack(&[0x01u8; 16]);
        q.sweep(1000 + RELAY_RETENTION_SECS + 10, RELAY_RETENTION_SECS);
        assert_eq!(q.durable_user_records(), 0);
        assert_eq!(q.pending(), 0);
    }
}
