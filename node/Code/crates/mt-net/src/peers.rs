// spec, раздел "Сетевой уровень → Выбор пиров" + Storage Card PeerRecord
//
// PeerRecord локальный (вне consensus state, [I-3] orthogonal).
// Hard quota = 8192 records (см. Storage Card); LRU eviction по
// last_seen_window. 4-уровневая diversity (/16, ASN, start_window, role).

use alloc::collections::{BTreeMap, BTreeSet};
use alloc::vec::Vec;

use crate::error::NetError;
use crate::payloads::IpAddrV;

pub const MAX_PEER_RECORDS: usize = 8192;
pub const PRUNING_IDLE_TAU1_MULTIPLIER: u64 = 8;
pub const ROTATION_PER_TAU2: usize = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PeerRole {
    Outbound,
    Inbound,
    Bootstrap,
    Anchor,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerRecord {
    pub node_id: [u8; 32],
    pub node_pubkey: Vec<u8>,
    pub ip_version: IpAddrV,
    pub ip: [u8; 16],
    pub port: u16,
    pub start_window: u64,
    pub last_seen_window: u64,
    pub asn: u32,
    pub prefix16: [u8; 2],
    pub role: PeerRole,
}

impl PeerRecord {
    pub fn ipv4_prefix16(&self) -> [u8; 2] {
        // For V4-mapped (last 4 bytes), /16 = first two octets
        match self.ip_version {
            IpAddrV::V4 => {
                let mut p = [0u8; 2];
                p.copy_from_slice(&self.ip[12..14]);
                p
            },
            IpAddrV::V6 => self.prefix16,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiversityViolation {
    DuplicateNodeId,
    SamePrefix16,
    SameAsn,
    SameStartWindowCohort,
}

#[derive(Debug)]
pub struct PeerTable {
    by_node_id: BTreeMap<[u8; 32], PeerRecord>,
    verified: BTreeSet<[u8; 32]>,
}

impl PeerTable {
    pub fn new() -> Self {
        PeerTable {
            by_node_id: BTreeMap::new(),
            verified: BTreeSet::new(),
        }
    }

    pub fn len(&self) -> usize {
        self.by_node_id.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_node_id.is_empty()
    }

    pub fn insert(&mut self, record: PeerRecord) -> Result<(), NetError> {
        if let Some(existing) = self.by_node_id.get_mut(&record.node_id) {
            if record.last_seen_window > existing.last_seen_window {
                existing.last_seen_window = record.last_seen_window;
                existing.role = record.role;
            }
            return Ok(());
        }
        if self.by_node_id.len() >= MAX_PEER_RECORDS {
            self.evict_one_lru()?;
        }
        self.by_node_id.insert(record.node_id, record);
        Ok(())
    }

    pub fn mark_verified(&mut self, node_id: &[u8; 32]) {
        if self.by_node_id.contains_key(node_id) {
            self.verified.insert(*node_id);
        }
    }

    pub fn is_verified(&self, node_id: &[u8; 32]) -> bool {
        self.verified.contains(node_id)
    }

    pub fn prune_stale(&mut self, current_window: u64, tau1: u64) -> usize {
        let cutoff = current_window.saturating_sub(PRUNING_IDLE_TAU1_MULTIPLIER * tau1);
        let to_remove: Vec<[u8; 32]> = self
            .by_node_id
            .iter()
            .filter_map(|(id, r)| {
                // Never prune verified peers solely on last_seen — they are
                // trusted history; only prune unverified stale.
                if !self.verified.contains(id) && r.last_seen_window < cutoff {
                    Some(*id)
                } else {
                    None
                }
            })
            .collect();
        for id in &to_remove {
            self.by_node_id.remove(id);
        }
        to_remove.len()
    }

    fn evict_one_lru(&mut self) -> Result<(), NetError> {
        // Evict oldest unverified by last_seen_window. If all are verified,
        // evict oldest verified (rare).
        let candidate = self
            .by_node_id
            .iter()
            .filter(|(id, _)| !self.verified.contains(*id))
            .min_by_key(|(_, r)| r.last_seen_window)
            .map(|(id, _)| *id);
        let target = match candidate {
            Some(id) => id,
            None => self
                .by_node_id
                .iter()
                .min_by_key(|(_, r)| r.last_seen_window)
                .map(|(id, _)| *id)
                .ok_or(NetError::InvalidPayloadField)?,
        };
        self.by_node_id.remove(&target);
        self.verified.remove(&target);
        Ok(())
    }

    pub fn select_diverse_outbound(
        &self,
        max_count: usize,
        start_window_cohort_size: u64,
    ) -> Vec<PeerRecord> {
        let mut chosen: Vec<PeerRecord> = Vec::new();
        let mut used_prefix16: BTreeSet<[u8; 2]> = BTreeSet::new();
        let mut used_asn: BTreeSet<u32> = BTreeSet::new();
        let mut used_cohort: BTreeSet<u64> = BTreeSet::new();
        // Prefer verified first (sorted by last_seen desc), then unverified by
        // last_seen desc.
        let mut sorted: Vec<&PeerRecord> = self.by_node_id.values().collect();
        sorted.sort_by(|a, b| {
            let av = self.verified.contains(&a.node_id);
            let bv = self.verified.contains(&b.node_id);
            bv.cmp(&av)
                .then(b.last_seen_window.cmp(&a.last_seen_window))
        });
        for r in sorted {
            if chosen.len() >= max_count {
                break;
            }
            let pfx = r.ipv4_prefix16();
            let cohort = r
                .start_window
                .checked_div(start_window_cohort_size)
                .unwrap_or(r.start_window);
            if used_prefix16.contains(&pfx) {
                continue;
            }
            if used_asn.contains(&r.asn) {
                continue;
            }
            if used_cohort.contains(&cohort) {
                continue;
            }
            used_prefix16.insert(pfx);
            used_asn.insert(r.asn);
            used_cohort.insert(cohort);
            chosen.push(r.clone());
        }
        chosen
    }
}

impl Default for PeerTable {
    fn default() -> Self {
        Self::new()
    }
}

pub fn check_diversity(records: &[PeerRecord]) -> Result<(), DiversityViolation> {
    let mut node_ids: BTreeSet<&[u8; 32]> = BTreeSet::new();
    let mut prefixes: BTreeSet<[u8; 2]> = BTreeSet::new();
    let mut asns: BTreeSet<u32> = BTreeSet::new();
    for r in records {
        if !node_ids.insert(&r.node_id) {
            return Err(DiversityViolation::DuplicateNodeId);
        }
        if !prefixes.insert(r.ipv4_prefix16()) {
            return Err(DiversityViolation::SamePrefix16);
        }
        if !asns.insert(r.asn) {
            return Err(DiversityViolation::SameAsn);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    fn make_peer(
        node_id_byte: u8,
        ip: [u8; 4],
        port: u16,
        start_window: u64,
        asn: u32,
    ) -> PeerRecord {
        let mut ip16 = [0u8; 16];
        ip16[12..].copy_from_slice(&ip);
        PeerRecord {
            node_id: [node_id_byte; 32],
            node_pubkey: vec![node_id_byte; 1952],
            ip_version: IpAddrV::V4,
            ip: ip16,
            port,
            start_window,
            last_seen_window: start_window + 100,
            asn,
            prefix16: [ip[0], ip[1]],
            role: PeerRole::Outbound,
        }
    }

    #[test]
    fn insert_and_lookup() {
        let mut t = PeerTable::new();
        let p = make_peer(0x11, [10, 0, 0, 1], 4242, 100, 1000);
        t.insert(p.clone()).unwrap();
        assert_eq!(t.len(), 1);
        assert!(t.by_node_id.contains_key(&[0x11; 32]));
    }

    #[test]
    fn upsert_updates_last_seen() {
        let mut t = PeerTable::new();
        let p1 = make_peer(0x11, [10, 0, 0, 1], 4242, 100, 1000);
        t.insert(p1).unwrap();
        let mut p2 = make_peer(0x11, [10, 0, 0, 1], 4242, 100, 1000);
        p2.last_seen_window = 999;
        t.insert(p2).unwrap();
        assert_eq!(t.by_node_id[&[0x11; 32]].last_seen_window, 999);
    }

    #[test]
    fn diversity_selector_rejects_same_prefix16() {
        let mut t = PeerTable::new();
        let p1 = make_peer(0x11, [10, 0, 0, 1], 4242, 100, 1000);
        let p2 = make_peer(0x22, [10, 0, 1, 1], 4242, 200, 2000); // same /16 = 10.0
        let p3 = make_peer(0x33, [11, 0, 0, 1], 4242, 300, 3000); // different /16 = 11.0
        t.insert(p1).unwrap();
        t.insert(p2).unwrap();
        t.insert(p3).unwrap();
        let chosen = t.select_diverse_outbound(10, 50);
        // Only one of p1/p2 (same /16) + p3 = 2 chosen
        assert_eq!(chosen.len(), 2);
    }

    #[test]
    fn diversity_selector_rejects_same_asn() {
        let mut t = PeerTable::new();
        let p1 = make_peer(0x11, [10, 0, 0, 1], 4242, 100, 1000);
        let p2 = make_peer(0x22, [11, 0, 0, 1], 4242, 200, 1000); // same asn
        t.insert(p1).unwrap();
        t.insert(p2).unwrap();
        let chosen = t.select_diverse_outbound(10, 50);
        assert_eq!(chosen.len(), 1);
    }

    #[test]
    fn diversity_selector_cohort_separation() {
        let mut t = PeerTable::new();
        let p1 = make_peer(0x11, [10, 0, 0, 1], 4242, 100, 1000);
        let p2 = make_peer(0x22, [11, 0, 0, 1], 4242, 110, 2000);
        let p3 = make_peer(0x33, [12, 0, 0, 1], 4242, 200, 3000);
        t.insert(p1).unwrap();
        t.insert(p2).unwrap();
        t.insert(p3).unwrap();
        // cohort_size=50: p1=2, p2=2, p3=4 — only one per cohort
        let chosen = t.select_diverse_outbound(10, 50);
        assert_eq!(chosen.len(), 2);
    }

    #[test]
    fn pruning_removes_stale_unverified() {
        let mut t = PeerTable::new();
        let mut p_old = make_peer(0x11, [10, 0, 0, 1], 4242, 100, 1000);
        p_old.last_seen_window = 100;
        let mut p_new = make_peer(0x22, [11, 0, 0, 1], 4242, 100, 2000);
        p_new.last_seen_window = 1000;
        t.insert(p_old).unwrap();
        t.insert(p_new).unwrap();
        let removed = t.prune_stale(2000, 60); // cutoff = 2000 - 8*60 = 1520
        assert_eq!(removed, 2); // both stale
    }

    #[test]
    fn pruning_preserves_verified() {
        let mut t = PeerTable::new();
        let mut p_old = make_peer(0x11, [10, 0, 0, 1], 4242, 100, 1000);
        p_old.last_seen_window = 100;
        t.insert(p_old).unwrap();
        t.mark_verified(&[0x11; 32]);
        let removed = t.prune_stale(2000, 60);
        assert_eq!(removed, 0);
        assert_eq!(t.len(), 1);
    }

    #[test]
    fn max_peer_records_quota_enforced_with_eviction() {
        let mut t = PeerTable::new();
        // Insert MAX_PEER_RECORDS — all unverified
        for i in 0..MAX_PEER_RECORDS {
            let mut ip = [10u8, 0, 0, 0];
            ip[2] = (i / 256) as u8;
            ip[3] = (i % 256) as u8;
            let mut p = make_peer(((i % 250) + 1) as u8, ip, 4242, 100, i as u32);
            // Make node_id unique per iteration
            p.node_id = {
                let mut id = [0u8; 32];
                id[0..8].copy_from_slice(&(i as u64).to_le_bytes());
                id
            };
            p.last_seen_window = i as u64;
            t.insert(p).unwrap();
        }
        assert_eq!(t.len(), MAX_PEER_RECORDS);
        // Insert one more — should evict
        let mut id_extra = [0u8; 32];
        id_extra[0..8].copy_from_slice(&(MAX_PEER_RECORDS as u64).to_le_bytes());
        let mut p_extra = make_peer(0xFF, [200, 0, 0, 1], 4242, 999, 99999);
        p_extra.node_id = id_extra;
        p_extra.last_seen_window = 1_000_000;
        t.insert(p_extra).unwrap();
        assert_eq!(t.len(), MAX_PEER_RECORDS);
        // Newest survived
        assert!(t.by_node_id.contains_key(&id_extra));
    }

    #[test]
    fn check_diversity_passes_for_diverse_set() {
        let p1 = make_peer(0x11, [10, 0, 0, 1], 4242, 100, 1000);
        let p2 = make_peer(0x22, [11, 0, 0, 1], 4242, 200, 2000);
        let p3 = make_peer(0x33, [12, 0, 0, 1], 4242, 300, 3000);
        assert!(check_diversity(&[p1, p2, p3]).is_ok());
    }

    #[test]
    fn check_diversity_fails_on_dup_node_id() {
        let p1 = make_peer(0x11, [10, 0, 0, 1], 4242, 100, 1000);
        let p2 = make_peer(0x11, [11, 0, 0, 1], 4242, 200, 2000);
        assert_eq!(
            check_diversity(&[p1, p2]),
            Err(DiversityViolation::DuplicateNodeId)
        );
    }
}
