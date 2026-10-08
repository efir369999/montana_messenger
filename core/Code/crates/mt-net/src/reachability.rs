// spec, Network layer -> "Reachability sensing and auto-steering"
// (ReachabilityAdvert layout + invariants).
//
// Transport-layer telemetry, outside consensus state ([I-3] orthogonal).
// The advert propagates over peer exchange; the aggregated map is advisory
// and ranks candidate entry points only. No state-root participation.

use alloc::vec::Vec;

use mt_codec::{write_bytes, write_u16, write_u32, write_u8};

use crate::error::NetError;

/// Wire size of a ReachabilityAdvert: 2 + 4 + 32 + 1 + 2 + 2 + 4.
pub const REACHABILITY_ADVERT_SIZE: usize = 47;

/// Per-vantage retained observation bound (mirrors the IBT online-nonce bound).
pub const MAX_OBSERVATIONS_PER_VANTAGE: usize = 256;

/// Distinct /16 source groups required to act on a reachability triple.
pub const REACHABILITY_QUORUM: usize = 3;

/// Highest transport profile index (T0..T4).
pub const PROFILE_MAX: u8 = 4;

/// Advisory record of one vantage's reachability to one peer on one transport
/// profile. Propagated over peer exchange; aggregated into the reachability map.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReachabilityAdvert {
    /// ISO-3166-1 alpha-2 of the observing vantage.
    pub country_code: [u8; 2],
    /// Autonomous system of the observing vantage.
    pub asn: u32,
    /// node_id of the observed peer.
    pub target_ref: [u8; 32],
    /// Transport profile observed (T0..T4 = 0..4).
    pub profile: u8,
    /// Corroborating observations with outcome = reachable.
    pub reachable_num: u16,
    /// Total observations for the triple.
    pub reachable_den: u16,
    /// Cached window_index of the latest observation.
    pub observed_window: u32,
}

fn is_iso_alpha(b: u8) -> bool {
    b.is_ascii_uppercase()
}

impl ReachabilityAdvert {
    pub fn encode(&self, buf: &mut Vec<u8>) {
        write_bytes(buf, &self.country_code);
        write_u32(buf, self.asn);
        write_bytes(buf, &self.target_ref);
        write_u8(buf, self.profile);
        write_u16(buf, self.reachable_num);
        write_u16(buf, self.reachable_den);
        write_u32(buf, self.observed_window);
    }

    pub fn decode(input: &[u8]) -> Result<Self, NetError> {
        if input.len() != REACHABILITY_ADVERT_SIZE {
            return Err(NetError::PayloadLengthMismatch);
        }
        let mut country_code = [0u8; 2];
        country_code.copy_from_slice(&input[0..2]);
        let mut asn_b = [0u8; 4];
        asn_b.copy_from_slice(&input[2..6]);
        let asn = u32::from_le_bytes(asn_b);
        let mut target_ref = [0u8; 32];
        target_ref.copy_from_slice(&input[6..38]);
        let profile = input[38];
        let mut num_b = [0u8; 2];
        num_b.copy_from_slice(&input[39..41]);
        let reachable_num = u16::from_le_bytes(num_b);
        let mut den_b = [0u8; 2];
        den_b.copy_from_slice(&input[41..43]);
        let reachable_den = u16::from_le_bytes(den_b);
        let mut win_b = [0u8; 4];
        win_b.copy_from_slice(&input[43..47]);
        let observed_window = u32::from_le_bytes(win_b);

        // Invariants ReachabilityAdvert (spec):
        // country_code is two ISO-3166-1 alpha-2 letters.
        if !is_iso_alpha(country_code[0]) || !is_iso_alpha(country_code[1]) {
            return Err(NetError::InvalidPayloadField);
        }
        // profile in T0..T4.
        if profile > PROFILE_MAX {
            return Err(NetError::InvalidPayloadField);
        }
        // reachable_den >= 1 and reachable_num <= reachable_den.
        if reachable_den == 0 || reachable_num > reachable_den {
            return Err(NetError::InvalidPayloadField);
        }

        Ok(ReachabilityAdvert {
            country_code,
            asn,
            target_ref,
            profile,
            reachable_num,
            reachable_den,
            observed_window,
        })
    }

    /// Ranking ratio (num, den). Advisory only; forms no consensus state.
    pub fn reachable_fraction(&self) -> (u16, u16) {
        (self.reachable_num, self.reachable_den)
    }

    /// Staleness gate: the advert is fresh when its observed_window lies within
    /// [known_window - staleness_bound, known_window]. The mesh-IBT staleness
    /// bound (7 * tau1) is supplied by the caller.
    pub fn is_fresh(&self, known_window: u32, staleness_bound: u32) -> bool {
        let lo = known_window.saturating_sub(staleness_bound);
        self.observed_window >= lo && self.observed_window <= known_window
    }
}

/// Aggregated, advisory reachability map. Ingests adverts keyed by
/// (country_code, asn, target_ref, profile); a triple becomes actionable only
/// when corroborated by at least REACHABILITY_QUORUM distinct /16 source groups
/// (the diversity unit of the outgoing-connection constraints). Bounded per
/// vantage by MAX_OBSERVATIONS_PER_VANTAGE; outside consensus state.
use alloc::collections::{BTreeMap, BTreeSet};

type TripleKey = ([u8; 2], u32, [u8; 32], u8);

#[derive(Debug, Clone)]
struct TripleAgg {
    sources: BTreeSet<[u8; 2]>,
    latest: ReachabilityAdvert,
}

#[derive(Debug, Default)]
pub struct ReachabilityMap {
    entries: BTreeMap<TripleKey, TripleAgg>,
}

/// A ranked, actionable entry candidate for auto-steering.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RankedEntry {
    pub target_ref: [u8; 32],
    pub profile: u8,
    pub reachable_num: u16,
    pub reachable_den: u16,
}

impl ReachabilityMap {
    pub fn new() -> Self {
        ReachabilityMap {
            entries: BTreeMap::new(),
        }
    }

    fn key(a: &ReachabilityAdvert) -> TripleKey {
        (a.country_code, a.asn, a.target_ref, a.profile)
    }

    /// Ingest an advert reported by a peer in `source_prefix16` (/16 of the
    /// reporter), valid at `known_window`. Stale adverts are rejected. The
    /// per-vantage entry count is bounded; on overflow the lowest-fraction
    /// triple for that vantage is evicted.
    pub fn ingest(
        &mut self,
        advert: ReachabilityAdvert,
        source_prefix16: [u8; 2],
        known_window: u32,
        staleness_bound: u32,
    ) -> bool {
        if !advert.is_fresh(known_window, staleness_bound) {
            return false;
        }
        let k = Self::key(&advert);
        let vantage = (advert.country_code, advert.asn);
        let entry = self.entries.entry(k).or_insert_with(|| TripleAgg {
            sources: BTreeSet::new(),
            latest: advert.clone(),
        });
        entry.sources.insert(source_prefix16);
        entry.latest = advert;
        self.enforce_vantage_bound(vantage);
        true
    }

    fn enforce_vantage_bound(&mut self, vantage: ([u8; 2], u32)) {
        let count = self
            .entries
            .keys()
            .filter(|(cc, asn, _, _)| (*cc, *asn) == vantage)
            .count();
        if count <= MAX_OBSERVATIONS_PER_VANTAGE {
            return;
        }
        // Evict the lowest reachable_fraction triple for this vantage.
        let victim = self
            .entries
            .iter()
            .filter(|((cc, asn, _, _), _)| (*cc, *asn) == vantage)
            .min_by(|(_, a), (_, b)| {
                let fa = a.latest.reachable_num as u32 * b.latest.reachable_den as u32;
                let fb = b.latest.reachable_num as u32 * a.latest.reachable_den as u32;
                fa.cmp(&fb)
            })
            .map(|(k, _)| *k);
        if let Some(k) = victim {
            self.entries.remove(&k);
        }
    }

    /// True when the triple is corroborated by at least REACHABILITY_QUORUM
    /// distinct /16 source groups.
    pub fn is_actionable(&self, advert: &ReachabilityAdvert) -> bool {
        self.entries
            .get(&Self::key(advert))
            .map(|e| e.sources.len() >= REACHABILITY_QUORUM)
            .unwrap_or(false)
    }

    /// Actionable entry candidates for a vantage, ranked by reachable_fraction
    /// descending (cross-multiplication, no floating point). Advisory ranking
    /// for auto-steering; the local IBT probe remains authoritative.
    pub fn ranked_for_vantage(&self, country_code: [u8; 2], asn: u32) -> Vec<RankedEntry> {
        let mut out: Vec<RankedEntry> = self
            .entries
            .iter()
            .filter(|((cc, a, _, _), agg)| {
                *cc == country_code && *a == asn && agg.sources.len() >= REACHABILITY_QUORUM
            })
            .map(|((_, _, target, profile), agg)| RankedEntry {
                target_ref: *target,
                profile: *profile,
                reachable_num: agg.latest.reachable_num,
                reachable_den: agg.latest.reachable_den,
            })
            .collect();
        out.sort_by(|x, y| {
            let lhs = x.reachable_num as u32 * y.reachable_den as u32;
            let rhs = y.reachable_num as u32 * x.reachable_den as u32;
            rhs.cmp(&lhs)
        });
        out
    }

    /// Reorder diversity-selected candidate node_ids by reachable_fraction for
    /// the given vantage, highest first. Candidates with an actionable map entry
    /// (>= REACHABILITY_QUORUM distinct /16) are ranked ahead of candidates with
    /// none; the latter keep their input relative order. Diversity is enforced by
    /// the caller (PeerTable::select_diverse_outbound); steering only reorders
    /// within the already-satisfied set, and the local IBT probe stays
    /// authoritative over this advisory order.
    pub fn steer(&self, candidates: &[[u8; 32]], country_code: [u8; 2], asn: u32) -> Vec<[u8; 32]> {
        let ranked = self.ranked_for_vantage(country_code, asn);
        // best (num, den) per target across its profiles
        let mut best: BTreeMap<[u8; 32], (u16, u16)> = BTreeMap::new();
        for e in &ranked {
            let cur = best.get(&e.target_ref).copied();
            let better = match cur {
                None => true,
                Some((n, d)) => {
                    (e.reachable_num as u32 * d as u32) > (n as u32 * e.reachable_den as u32)
                },
            };
            if better {
                best.insert(e.target_ref, (e.reachable_num, e.reachable_den));
            }
        }
        let mut have: Vec<[u8; 32]> = Vec::new();
        let mut none: Vec<[u8; 32]> = Vec::new();
        for c in candidates {
            if best.contains_key(c) {
                have.push(*c);
            } else {
                none.push(*c);
            }
        }
        have.sort_by(|x, y| {
            let (xn, xd) = best[x];
            let (yn, yd) = best[y];
            let lhs = xn as u32 * yd as u32;
            let rhs = yn as u32 * xd as u32;
            rhs.cmp(&lhs)
        });
        have.extend(none);
        have
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec::Vec;

    fn sample() -> ReachabilityAdvert {
        ReachabilityAdvert {
            country_code: *b"AM",
            asn: 0x0001_0203,
            target_ref: [0x11u8; 32],
            profile: 1,
            reachable_num: 3,
            reachable_den: 4,
            observed_window: 0x0000_4ec0,
        }
    }

    #[test]
    fn roundtrip() {
        let a = sample();
        let mut buf = Vec::new();
        a.encode(&mut buf);
        assert_eq!(buf.len(), REACHABILITY_ADVERT_SIZE);
        let b = ReachabilityAdvert::decode(&buf).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn kat_byte_exact() {
        // Binding KAT: fixed advert -> exact 47-byte little-endian encoding.
        let a = sample();
        let mut buf = Vec::new();
        a.encode(&mut buf);
        let mut expected = Vec::new();
        expected.extend_from_slice(b"AM"); // country_code
        expected.extend_from_slice(&[0x03, 0x02, 0x01, 0x00]); // asn LE
        expected.extend_from_slice(&[0x11u8; 32]); // target_ref
        expected.push(0x01); // profile
        expected.extend_from_slice(&[0x03, 0x00]); // reachable_num LE
        expected.extend_from_slice(&[0x04, 0x00]); // reachable_den LE
        expected.extend_from_slice(&[0xc0, 0x4e, 0x00, 0x00]); // observed_window LE
        assert_eq!(buf, expected);
    }

    #[test]
    fn reject_wrong_length() {
        assert!(matches!(
            ReachabilityAdvert::decode(&[0u8; 46]),
            Err(NetError::PayloadLengthMismatch)
        ));
    }

    #[test]
    fn reject_bad_country() {
        let mut a = sample();
        a.country_code = *b"a1";
        let mut buf = Vec::new();
        a.encode(&mut buf);
        assert!(matches!(
            ReachabilityAdvert::decode(&buf),
            Err(NetError::InvalidPayloadField)
        ));
    }

    #[test]
    fn reject_bad_profile() {
        let mut a = sample();
        a.profile = 5;
        let mut buf = Vec::new();
        a.encode(&mut buf);
        assert!(matches!(
            ReachabilityAdvert::decode(&buf),
            Err(NetError::InvalidPayloadField)
        ));
    }

    #[test]
    fn reject_den_zero_and_num_gt_den() {
        let mut a = sample();
        a.reachable_den = 0;
        let mut buf = Vec::new();
        a.encode(&mut buf);
        assert!(matches!(
            ReachabilityAdvert::decode(&buf),
            Err(NetError::InvalidPayloadField)
        ));

        let mut a2 = sample();
        a2.reachable_num = 5;
        a2.reachable_den = 4;
        let mut buf2 = Vec::new();
        a2.encode(&mut buf2);
        assert!(matches!(
            ReachabilityAdvert::decode(&buf2),
            Err(NetError::InvalidPayloadField)
        ));
    }

    #[test]
    fn freshness_window() {
        let a = sample(); // observed_window = 0x4ec0 = 20160
        assert!(a.is_fresh(20160, 100));
        assert!(a.is_fresh(20200, 100)); // within [20100, 20200]
        assert!(!a.is_fresh(20300, 100)); // below 20200 lower bound
        assert!(!a.is_fresh(20159, 100)); // above known
    }

    #[test]
    fn map_quorum_gate() {
        let mut m = ReachabilityMap::new();
        let a = sample();
        // two distinct /16 -> not actionable
        m.ingest(a.clone(), [10, 0], 20160, 100);
        m.ingest(a.clone(), [11, 0], 20160, 100);
        assert!(!m.is_actionable(&a));
        // third distinct /16 -> actionable
        m.ingest(a.clone(), [12, 0], 20160, 100);
        assert!(m.is_actionable(&a));
    }

    #[test]
    fn map_same_prefix_not_quorum() {
        let mut m = ReachabilityMap::new();
        let a = sample();
        // three reports from the SAME /16 -> still one distinct source
        m.ingest(a.clone(), [10, 0], 20160, 100);
        m.ingest(a.clone(), [10, 0], 20160, 100);
        m.ingest(a.clone(), [10, 0], 20160, 100);
        assert!(!m.is_actionable(&a));
    }

    #[test]
    fn map_stale_rejected() {
        let mut m = ReachabilityMap::new();
        let a = sample(); // observed_window = 20160
        assert!(!m.ingest(a.clone(), [10, 0], 21000, 100)); // 20160 < 20900 lower bound
        assert!(m.is_empty());
    }

    #[test]
    fn map_ranking_desc() {
        let mut m = ReachabilityMap::new();
        let mut hi = sample();
        hi.target_ref = [0xAAu8; 32];
        hi.reachable_num = 9;
        hi.reachable_den = 10; // 0.9
        let mut lo = sample();
        lo.target_ref = [0xBBu8; 32];
        lo.reachable_num = 1;
        lo.reachable_den = 10; // 0.1
        for src in [[1u8, 0], [2, 0], [3, 0]] {
            m.ingest(hi.clone(), src, 20160, 100);
            m.ingest(lo.clone(), src, 20160, 100);
        }
        let ranked = m.ranked_for_vantage(*b"AM", 0x0001_0203);
        assert_eq!(ranked.len(), 2);
        assert_eq!(ranked[0].target_ref, [0xAAu8; 32]); // higher fraction first
        assert_eq!(ranked[1].target_ref, [0xBBu8; 32]);
    }

    #[test]
    fn steer_orders_ranked_first_then_unranked() {
        let mut m = ReachabilityMap::new();
        let a = [0xAAu8; 32];
        let b = [0xBBu8; 32];
        let c = [0xCCu8; 32];
        let mk = |t: [u8; 32], n: u16, d: u16| {
            let mut x = sample();
            x.target_ref = t;
            x.reachable_num = n;
            x.reachable_den = d;
            x
        };
        for src in [[1u8, 0], [2, 0], [3, 0]] {
            m.ingest(mk(a, 1, 10), src, 20160, 100); // 0.1
            m.ingest(mk(c, 9, 10), src, 20160, 100); // 0.9
        }
        // b has no map entry; candidates in arbitrary order [a, b, c]
        let out = m.steer(&[a, b, c], *b"AM", 0x0001_0203);
        // ranked desc (c=0.9, a=0.1) then unranked b
        assert_eq!(out, vec![c, a, b]);
    }

    #[test]
    fn steer_empty_map_preserves_order() {
        let m = ReachabilityMap::new();
        let a = [0xAAu8; 32];
        let b = [0xBBu8; 32];
        assert_eq!(m.steer(&[a, b], *b"AM", 1), vec![a, b]);
    }
}
