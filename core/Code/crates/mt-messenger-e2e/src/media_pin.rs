//! Stage 9 (second front) — media pinning by devices. During archive catch-up (Stages 3/4) a device
//! walks each message's AttachmentRef (Content 0x05, first front), fetches every not-yet-held chunk,
//! verifies SHA-256(sealed) == blob_id, and stores it. So media replicates onto all devices like
//! history — durability ∝ number of devices, not "who clicked". Pinning is idempotent and bounded by a
//! per-device quota with LRU eviction by send_time (soft degradation: old media drops first, the
//! manifest remains).

use crate::media::blob_id;
use std::collections::HashMap;

pub const PIN_QUOTA: u64 = 8_589_934_592; // 8 GiB default (device config)

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PinOutcome {
    Pinned,
    Duplicate,
    Corrupt,  // SHA-256(sealed) != blob_id
    TooLarge, // a single blob larger than the whole quota cannot be held
}

struct Entry {
    bytes: u64,
    send_time: u64,
}

pub struct PinStore {
    quota: u64,
    used: u64,
    entries: HashMap<[u8; 32], Entry>,
}

impl PinStore {
    pub fn new(quota: u64) -> Self {
        Self {
            quota,
            used: 0,
            entries: HashMap::new(),
        }
    }

    pub fn used_bytes(&self) -> u64 {
        self.used
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn has(&self, id: &[u8; 32]) -> bool {
        self.entries.contains_key(id)
    }

    /// Pin one sealed blob. Verifies content addressing (SHA-256(sealed) == expected_id), is idempotent,
    /// and evicts LRU by send_time when the quota would be exceeded (manifest stays; the file drops).
    pub fn pin(&mut self, expected_id: &[u8; 32], sealed: &[u8], send_time: u64) -> PinOutcome {
        if &blob_id(sealed) != expected_id {
            return PinOutcome::Corrupt;
        }
        if self.entries.contains_key(expected_id) {
            return PinOutcome::Duplicate;
        }
        let size = sealed.len() as u64;
        if size > self.quota {
            return PinOutcome::TooLarge;
        }
        while self.used + size > self.quota {
            // evict the lowest send_time entry (LRU by message time)
            let victim = self
                .entries
                .iter()
                .min_by_key(|(_, e)| e.send_time)
                .map(|(k, _)| *k);
            match victim {
                Some(k) => {
                    if let Some(e) = self.entries.remove(&k) {
                        self.used -= e.bytes;
                    }
                },
                None => break,
            }
        }
        self.entries.insert(
            *expected_id,
            Entry {
                bytes: size,
                send_time,
            },
        );
        self.used += size;
        PinOutcome::Pinned
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::media::seal_blob;

    fn blob(tag: u8, len: usize) -> Vec<u8> {
        seal_blob(&[0x66; 32], &[tag; 12], &vec![tag; len])
    }

    #[test]
    fn pin_verifies_and_is_idempotent() {
        let mut store = PinStore::new(PIN_QUOTA);
        let b = blob(1, 100);
        let id = blob_id(&b);
        assert_eq!(store.pin(&id, &b, 1000), PinOutcome::Pinned);
        assert_eq!(store.pin(&id, &b, 1000), PinOutcome::Duplicate); // idempotent
        assert_eq!(store.len(), 1);
        assert!(store.has(&id));
    }

    #[test]
    fn corrupt_rejected() {
        let mut store = PinStore::new(PIN_QUOTA);
        let b = blob(1, 100);
        let wrong_id = [0x00u8; 32];
        assert_eq!(store.pin(&wrong_id, &b, 1000), PinOutcome::Corrupt);
        assert_eq!(store.len(), 0);
    }

    #[test]
    fn quota_lru_eviction_by_send_time() {
        // quota fits ~2 blobs; a third eviction drops the oldest send_time first.
        let b1 = blob(1, 400);
        let b2 = blob(2, 400);
        let b3 = blob(3, 400);
        let q = (b1.len() + b2.len()) as u64; // room for exactly two
        let mut store = PinStore::new(q);
        assert_eq!(store.pin(&blob_id(&b1), &b1, 100), PinOutcome::Pinned); // oldest
        assert_eq!(store.pin(&blob_id(&b2), &b2, 200), PinOutcome::Pinned);
        assert_eq!(store.pin(&blob_id(&b3), &b3, 300), PinOutcome::Pinned); // evicts b1 (send_time 100)
        assert!(!store.has(&blob_id(&b1)), "oldest evicted");
        assert!(store.has(&blob_id(&b2)));
        assert!(store.has(&blob_id(&b3)));
        assert!(store.used_bytes() <= q);
    }

    #[test]
    fn oversize_blob_rejected() {
        let mut store = PinStore::new(100);
        let big = blob(1, 500);
        assert_eq!(store.pin(&blob_id(&big), &big, 1000), PinOutcome::TooLarge);
        assert!(store.is_empty());
    }
}
