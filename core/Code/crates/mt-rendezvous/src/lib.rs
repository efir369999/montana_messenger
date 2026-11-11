//! DHT rendezvous (Montana P2P Network, Stage 4): byte-exact core of endpoint lookup via
//! Mainline BitTorrent DHT (BEP44 mutable). `dht_key` — ed25519 admission-token ([P2P-5]/
//! A-2 [I-16]): forging it quantumly yields only a DoS redirect, NOT a breach; overlay/content/
//! identity are PQ (Stage 1). Delivery integrity is caught by the E2E receipt (R1), not the rendezvous signature.
//! The Mainline DHT transport (BEP5 put/get) is a separate network layer on top of this core.

use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use mt_codec::{write_bytes, write_u8, CanonicalEncode};
use sha1::{Digest, Sha1};
use thiserror::Error;

pub const DHT_SEED_LEN: usize = 32;
pub const DK_LEN: usize = 32; // ed25519 pubkey
pub const SALT_LEN: usize = 20;
pub const TARGET_LEN: usize = 20; // SHA1
pub const OVERLAY_ADDR_LEN: usize = mt_crypto::HASH_SIZE; // S-3: overlay_addr — SHA-256, SSOT
pub const PQ_HINT_LEN: usize = 32;
/// BEP44 verdict: body `v` ≤ 1000 B.
pub const MAX_RECORD_BYTES: usize = 1000;
/// ep_count and addr_len are one byte (u8) each: at most 255 (F-1 anti-truncation).
pub const MAX_ENDPOINTS: usize = 255;
pub const MAX_ENDPOINT_ADDR: usize = 255;
/// BEP44 seq is i64 (mainline). The seq domain is capped at i64::MAX so u64→i64 does not wrap
/// to negative and the signature matches mainline encode_signable byte for byte (F-3).
pub const MAX_SEQ: u64 = i64::MAX as u64;

pub mod dht;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum RvError {
    #[error("truncated")]
    Truncated,
    #[error("bad endpoint kind {0:#04x}")]
    BadKind(u8),
    #[error("record exceeds BEP44 1000 B ({0})")]
    TooLarge(usize),
    #[error("length mismatch")]
    LengthMismatch,
    #[error("too many endpoints {0} (max 255)")]
    TooManyEndpoints(usize),
    #[error("endpoint addr too long {0} (max 255)")]
    AddrTooLong(usize),
    #[error("seq {0} exceeds i64::MAX (BEP44)")]
    SeqOutOfRange(u64),
    #[error("dht: {0}")]
    Dht(String),
}

// --- dht_key (ed25519 admission, HKDF branch of master_seed) ---

/// dht_seed = HKDF-Expand(master_seed, info="mt-dht-key", L=32). The secret never leaves the leaf.
pub fn derive_dht_seed(master_seed: &[u8]) -> [u8; DHT_SEED_LEN] {
    let okm = mt_mnemonic::hkdf_expand(master_seed, mt_codec::domain::DHT_KEY, DHT_SEED_LEN);
    let mut s = [0u8; DHT_SEED_LEN];
    s.copy_from_slice(&okm);
    s
}

// [I-16] A-2: ed25519 is the BEP44 admission token (a BitTorrent mandate; ≤1000 B does not fit
// ML-DSA 3309 B). Compromising the key = DoS redirect, not a breach; overlay/content/identity are PQ.
pub fn dht_signing_key(dht_seed: &[u8; DHT_SEED_LEN]) -> SigningKey {
    SigningKey::from_bytes(dht_seed)
}

pub fn dht_pubkey(sk: &SigningKey) -> [u8; DK_LEN] {
    sk.verifying_key().to_bytes()
}

// --- BEP44 target / salt ---

/// salt = SHA-256("mt-rv-salt" ‖ 0x00 ‖ session_id ‖ epoch_index_8B_LE)[0..20]. Per-pair,
/// per-epoch: rotates, known only to the two parties (session_id is opaque to the network).
pub fn derive_salt(session_id: &[u8; 32], epoch_index: u64) -> [u8; SALT_LEN] {
    let h = mt_crypto::hash(
        mt_codec::domain::RV_SALT,
        &[session_id, &epoch_index.to_le_bytes()],
    );
    let mut salt = [0u8; SALT_LEN];
    salt.copy_from_slice(&h[..SALT_LEN]);
    salt
}

/// target = SHA1(dk ‖ salt). SHA1 is mandated by BEP44, not our choice (admission token, not PQ).
pub fn derive_target(dk: &[u8; DK_LEN], salt: &[u8; SALT_LEN]) -> [u8; TARGET_LEN] {
    let mut h = Sha1::new();
    h.update(dk);
    h.update(salt);
    h.finalize().into()
}

// --- RendezvousRecord (BEP44 body v, byte-exact) ---
// Versioning: deliberately no version byte. The record is ephemeral (valid_until is a short
// window), both sides are version-synchronous via protocol bump; the long-lived cross-version
// carrier (QRBootstrap) is versioned separately. A format change = bump, not runtime negotiation.

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Endpoint {
    pub kind: u8, // 0x01=relay-circuit, 0x02=direct-v6, 0x03=direct-v4
    pub addr: Vec<u8>,
}

pub const EP_RELAY_CIRCUIT: u8 = 0x01;
pub const EP_DIRECT_V6: u8 = 0x02;
pub const EP_DIRECT_V4: u8 = 0x03;

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct RendezvousRecord {
    pub overlay_addr: [u8; OVERLAY_ADDR_LEN],
    pub endpoints: Vec<Endpoint>, // ep_count = len (u8)
    pub pq_hint: [u8; PQ_HINT_LEN],
    pub seq: u64,
    pub valid_until: u64,
}

impl CanonicalEncode for RendezvousRecord {
    fn encode(&self, buf: &mut Vec<u8>) {
        debug_assert!(
            self.endpoints.len() <= MAX_ENDPOINTS,
            "F-1: ep_count u8 overflow"
        );
        write_bytes(buf, &self.overlay_addr);
        write_u8(buf, self.endpoints.len() as u8);
        for ep in &self.endpoints {
            write_u8(buf, ep.kind);
            write_u8(buf, ep.addr.len() as u8);
            write_bytes(buf, &ep.addr);
        }
        write_bytes(buf, &self.pq_hint);
        write_bytes(buf, &self.seq.to_le_bytes());
        write_bytes(buf, &self.valid_until.to_le_bytes());
    }
}

impl RendezvousRecord {
    /// Structural validity before signing/put: fields fit the u8 counters and seq fits i64
    /// (F-1/F-3). Guarantees roundtrip decode(encode(x))==x and agreement with mainline.
    pub fn validate(&self, seq: u64) -> Result<(), RvError> {
        if self.endpoints.len() > MAX_ENDPOINTS {
            return Err(RvError::TooManyEndpoints(self.endpoints.len()));
        }
        for ep in &self.endpoints {
            if ep.addr.len() > MAX_ENDPOINT_ADDR {
                return Err(RvError::AddrTooLong(ep.addr.len()));
            }
        }
        if seq > MAX_SEQ {
            return Err(RvError::SeqOutOfRange(seq));
        }
        Ok(())
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = Vec::new();
        self.encode(&mut b);
        b
    }

    pub fn decode(input: &[u8]) -> Result<Self, RvError> {
        // overlay_addr32 ep_count1 [kind1 addr_len1 addr]* pq_hint32 seq8 valid_until8
        let min = OVERLAY_ADDR_LEN + 1 + PQ_HINT_LEN + 8 + 8;
        if input.len() < min {
            return Err(RvError::Truncated);
        }
        let mut o = 0;
        let mut overlay_addr = [0u8; OVERLAY_ADDR_LEN];
        overlay_addr.copy_from_slice(&input[o..o + OVERLAY_ADDR_LEN]);
        o += OVERLAY_ADDR_LEN;
        let ep_count = input[o] as usize;
        o += 1;
        // G-1: each endpoint is ≥2 B (kind+addr_len); do not reserve memory for a
        // counter not backed by data (amplification DoS).
        if input.len() - o < ep_count * 2 {
            return Err(RvError::Truncated);
        }
        let mut endpoints = Vec::with_capacity(ep_count);
        for _ in 0..ep_count {
            if input.len() < o + 2 {
                return Err(RvError::Truncated);
            }
            let kind = input[o];
            if !matches!(kind, EP_RELAY_CIRCUIT | EP_DIRECT_V6 | EP_DIRECT_V4) {
                return Err(RvError::BadKind(kind));
            }
            let addr_len = input[o + 1] as usize;
            o += 2;
            if input.len() < o + addr_len {
                return Err(RvError::Truncated);
            }
            endpoints.push(Endpoint {
                kind,
                addr: input[o..o + addr_len].to_vec(),
            });
            o += addr_len;
        }
        if input.len() != o + PQ_HINT_LEN + 8 + 8 {
            return Err(RvError::LengthMismatch);
        }
        let mut pq_hint = [0u8; PQ_HINT_LEN];
        pq_hint.copy_from_slice(&input[o..o + PQ_HINT_LEN]);
        o += PQ_HINT_LEN;
        let seq = u64::from_le_bytes(input[o..o + 8].try_into().map_err(|_| RvError::Truncated)?);
        o += 8;
        let valid_until =
            u64::from_le_bytes(input[o..o + 8].try_into().map_err(|_| RvError::Truncated)?);
        Ok(Self {
            overlay_addr,
            endpoints,
            pq_hint,
            seq,
            valid_until,
        })
    }
}

/// Resolve the physical address from a DHT record endpoint (replaces the hardcoded address, Stage 4).
/// v4 addr = 4B ip ‖ 2B port BE; v6 = 16B ip ‖ 2B port BE. relay-circuit is not a raw SocketAddr.
pub fn resolve_endpoint(ep: &Endpoint) -> Option<std::net::SocketAddr> {
    use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
    match ep.kind {
        EP_DIRECT_V4 if ep.addr.len() == 6 => {
            let ip = Ipv4Addr::new(ep.addr[0], ep.addr[1], ep.addr[2], ep.addr[3]);
            let port = u16::from_be_bytes([ep.addr[4], ep.addr[5]]);
            Some(SocketAddr::new(IpAddr::V4(ip), port))
        },
        EP_DIRECT_V6 if ep.addr.len() == 18 => {
            let mut o = [0u8; 16];
            o.copy_from_slice(&ep.addr[..16]);
            let port = u16::from_be_bytes([ep.addr[16], ep.addr[17]]);
            Some(SocketAddr::new(IpAddr::V6(Ipv6Addr::from(o)), port))
        },
        _ => None, // relay-circuit / invalid length: resolved via the overlay layer, not a socket
    }
}

/// Globally routable unicast? Rejects loopback / private / link-local /
/// unspecified / multicast / broadcast. The public rendezvous path must filter
/// an address from the DHT with this predicate BEFORE connect (F-2: otherwise a DHT record points the node at
/// the victim's internal network: SSRF). LAN mesh / self-host use the raw resolve_endpoint.
pub fn is_global_unicast(addr: &std::net::SocketAddr) -> bool {
    use std::net::{IpAddr, Ipv4Addr};
    fn v4_global(v4: &Ipv4Addr) -> bool {
        let o = v4.octets();
        !(v4.is_loopback()
            || v4.is_private()
            || v4.is_link_local()
            || v4.is_unspecified()
            || v4.is_multicast()
            || v4.is_broadcast()
            || o[0] == 0
            || (o[0] == 100 && (o[1] & 0xc0) == 0x40)) // 100.64.0.0/10 CGNAT (RFC 6598)
    }
    match addr.ip() {
        IpAddr::V4(v4) => v4_global(&v4),
        IpAddr::V6(v6) => {
            // IPv4-mapped (::ffff:x.x.x.x): the OS routes to the embedded v4, so
            // filter by v4 rules; otherwise ::ffff:127.0.0.1 / ::ffff:169.254.169.254
            // bypass the SSRF filter (is_loopback matches only ::1).
            if let Some(v4) = v6.to_ipv4_mapped() {
                return v4_global(&v4);
            }
            let s = v6.segments();
            let unique_local = (s[0] & 0xfe00) == 0xfc00; // fc00::/7
            let link_local = (s[0] & 0xffc0) == 0xfe80; // fe80::/10
            let doc = s[0] == 0x2001 && s[1] == 0x0db8; // 2001:db8::/32 (RFC 3849)
            !(v6.is_loopback()
                || v6.is_unspecified()
                || v6.is_multicast()
                || unique_local
                || link_local
                || doc)
        },
    }
}

/// Public DHT path: resolve + SSRF filter (F-2). Returns an address only if it is
/// globally routable. LAN/self-host: resolve_endpoint without the filter.
pub fn resolve_endpoint_public(ep: &Endpoint) -> Option<std::net::SocketAddr> {
    resolve_endpoint(ep).filter(is_global_unicast)
}

// --- BEP44 ed25519 signature (admission token, [P2P-5]) ---

/// Canonical BEP44 signing buffer for mutable-with-salt: bencoded salt/seq/v fields in a
/// fixed order (BEP44 standard). v is the RendezvousRecord bytes.
fn bep44_sign_buffer(salt: &[u8], seq: u64, v: &[u8]) -> Vec<u8> {
    let mut b = Vec::new();
    b.extend_from_slice(b"4:salt");
    b.extend_from_slice(format!("{}:", salt.len()).as_bytes());
    b.extend_from_slice(salt);
    b.extend_from_slice(b"3:seqi");
    b.extend_from_slice(seq.to_string().as_bytes());
    b.extend_from_slice(b"e1:v");
    b.extend_from_slice(format!("{}:", v.len()).as_bytes());
    b.extend_from_slice(v);
    b
}

/// Sign a rendezvous record with dht_key (ed25519 over the BEP44 buffer salt‖seq‖v).
pub fn sign_record(
    sk: &SigningKey,
    salt: &[u8; SALT_LEN],
    seq: u64,
    record: &RendezvousRecord,
) -> Result<Signature, RvError> {
    record.validate(seq)?;
    let v = record.to_bytes();
    sign_bep44(sk, salt, seq, &v)
}

/// Low-level signature over a ready body v (SSOT of signing; sign_record and prepare_batch
/// use it so the record is encoded exactly once — O-1).
pub(crate) fn sign_bep44(
    sk: &SigningKey,
    salt: &[u8; SALT_LEN],
    seq: u64,
    v: &[u8],
) -> Result<Signature, RvError> {
    if v.len() > MAX_RECORD_BYTES {
        return Err(RvError::TooLarge(v.len()));
    }
    Ok(sk.sign(&bep44_sign_buffer(salt, seq, v)))
}

/// Verify a rendezvous record against dk (admission token; NOT a PQ integrity guarantee).
/// The subscriber must separately check record.overlay_addr against the friend's overlay_addr (Stage 1)
/// and delivery integrity via the E2E receipt (R1).
pub fn verify_record(
    dk: &[u8; DK_LEN],
    salt: &[u8; SALT_LEN],
    seq: u64,
    record: &RendezvousRecord,
    sig: &Signature,
) -> bool {
    let vk = match VerifyingKey::from_bytes(dk) {
        Ok(k) => k,
        Err(_) => return false,
    };
    let v = record.to_bytes();
    vk.verify(&bep44_sign_buffer(salt, seq, &v), sig).is_ok()
}

/// DEV-051 / §595 [P2P-5] first line: check that the rendezvous record is bound to the
/// friend's identity. `overlay_addr` in the record must equal `overlay_addr(friend's account_id)`
/// (account_id is known to the subscriber from the E2E session). Even if the ed25519 admission
/// is forged quantumly, a forged overlay address is caught here → the redirect stays a
/// DoS class, not a breach of identity/content. Called by the RendezvousRecord consumer
/// BEFORE trusting overlay_addr; ed25519 verify (verify_record) and this check are independent.
pub fn record_binds_account(
    record: &RendezvousRecord,
    friend_account_id: &[u8; OVERLAY_ADDR_LEN],
) -> bool {
    record.overlay_addr == mt_overlay::overlay_addr(friend_account_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> RendezvousRecord {
        RendezvousRecord {
            overlay_addr: [0xAB; 32],
            endpoints: vec![
                Endpoint {
                    kind: EP_RELAY_CIRCUIT,
                    addr: vec![0x01, 0x02, 0x03],
                },
                Endpoint {
                    kind: EP_DIRECT_V6,
                    addr: vec![0x0A; 16],
                },
            ],
            pq_hint: [0xCD; 32],
            seq: 42,
            valid_until: 1_000_000,
        }
    }

    #[test]
    fn record_roundtrip_and_reject_bad_kind() {
        let r = sample();
        assert_eq!(RendezvousRecord::decode(&r.to_bytes()).unwrap(), r);
        // garbage kind
        let mut b = r.to_bytes();
        b[33] = 0x09; // first endpoint kind
        assert!(matches!(
            RendezvousRecord::decode(&b),
            Err(RvError::BadKind(0x09))
        ));
    }

    #[test]
    fn dht_key_deterministic_from_master_seed() {
        let master = [0x42u8; 64];
        let s1 = derive_dht_seed(&master);
        let s2 = derive_dht_seed(&master);
        assert_eq!(s1, s2, "determinism from master_seed");
        let sk = dht_signing_key(&s1);
        let dk = dht_pubkey(&sk);
        // different master → different key
        let dk2 = dht_pubkey(&dht_signing_key(&derive_dht_seed(&[0x43u8; 64])));
        assert_ne!(dk, dk2);
    }

    #[test]
    fn sign_verify_admission_and_tamper_fails() {
        let master = [0x42u8; 64];
        let sk = dht_signing_key(&derive_dht_seed(&master));
        let dk = dht_pubkey(&sk);
        let salt = derive_salt(&[0x33; 32], 7);
        let r = sample();
        let sig = sign_record(&sk, &salt, r.seq, &r).unwrap();
        assert!(verify_record(&dk, &salt, r.seq, &r, &sig));
        // foreign seq: the signature will not match (BEP44 anti-rollback)
        assert!(!verify_record(&dk, &salt, r.seq + 1, &r, &sig));
        // forged record
        let mut r2 = r.clone();
        r2.overlay_addr[0] ^= 1;
        assert!(!verify_record(&dk, &salt, r.seq, &r2, &sig));
        // foreign dk
        let dk2 = dht_pubkey(&dht_signing_key(&derive_dht_seed(&[0x99u8; 64])));
        assert!(!verify_record(&dk2, &salt, r.seq, &r, &sig));
    }

    #[test]
    fn resolve_endpoint_v4_v6() {
        let v4 = Endpoint {
            kind: EP_DIRECT_V4,
            addr: vec![203, 0, 113, 5, 0x20, 0xFC],
        };
        assert_eq!(
            resolve_endpoint(&v4).unwrap().to_string(),
            "203.0.113.5:8444"
        );
        let mut a6 = vec![0u8; 16];
        a6[15] = 1;
        a6.extend_from_slice(&8444u16.to_be_bytes());
        let v6 = Endpoint {
            kind: EP_DIRECT_V6,
            addr: a6,
        };
        assert_eq!(resolve_endpoint(&v6).unwrap().to_string(), "[::1]:8444");
        // relay-circuit does not resolve to a raw socket
        assert!(resolve_endpoint(&Endpoint {
            kind: EP_RELAY_CIRCUIT,
            addr: vec![1, 2, 3]
        })
        .is_none());
        // invalid length
        assert!(resolve_endpoint(&Endpoint {
            kind: EP_DIRECT_V4,
            addr: vec![1, 2]
        })
        .is_none());
    }

    #[test]
    fn salt_target_kat_oracle() {
        // Oracle: python hashlib.sha256/sha1 (Pass 25): byte-exact for cross-client.
        let salt = derive_salt(&[0x33; 32], 7);
        assert_eq!(
            hex::encode(salt),
            "93c7c3fbad00768cee189aedc2ef57738d55ef38"
        );
        let target = derive_target(&[0x11; 32], &salt);
        assert_eq!(
            hex::encode(target),
            "db1c2182fd6a0029df27462bf2d1cfad598567cb"
        );
    }

    #[test]
    fn record_byte_layout_kat_oracle() {
        // G-3: independent python-oracle (struct-concat) — cross-client byte-exact.
        let r = sample();
        assert_eq!(
            hex::encode(r.to_bytes()),
            "abababababababababababababababababababababababababababababababab02010301020302100a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0acdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd2a0000000000000040420f0000000000"
        );
    }

    #[test]
    fn roundtrip_zero_endpoints_and_truncated_tail() {
        // F-7: 0 endpoints: boundary roundtrip.
        let r = RendezvousRecord {
            overlay_addr: [0x11; 32],
            endpoints: vec![],
            pq_hint: [0x22; 32],
            seq: 0,
            valid_until: 0,
        };
        assert_eq!(RendezvousRecord::decode(&r.to_bytes()).unwrap(), r);
        // truncated tail → Truncated/LengthMismatch, not a panic
        let b = r.to_bytes();
        assert!(RendezvousRecord::decode(&b[..b.len() - 1]).is_err());
        // extra trailing byte → LengthMismatch (canonicity)
        let mut b2 = r.to_bytes();
        b2.push(0x00);
        assert_eq!(RendezvousRecord::decode(&b2), Err(RvError::LengthMismatch));
    }

    #[test]
    fn validate_rejects_oversized_and_seq() {
        // F-1: >255 endpoints
        let too_many = RendezvousRecord {
            overlay_addr: [0; 32],
            endpoints: vec![
                Endpoint {
                    kind: EP_DIRECT_V4,
                    addr: vec![0; 6]
                };
                256
            ],
            pq_hint: [0; 32],
            seq: 0,
            valid_until: 0,
        };
        assert!(matches!(
            too_many.validate(0),
            Err(RvError::TooManyEndpoints(256))
        ));
        // F-1: addr > 255
        let long_addr = RendezvousRecord {
            overlay_addr: [0; 32],
            endpoints: vec![Endpoint {
                kind: EP_DIRECT_V4,
                addr: vec![0; 256],
            }],
            pq_hint: [0; 32],
            seq: 0,
            valid_until: 0,
        };
        assert!(matches!(
            long_addr.validate(0),
            Err(RvError::AddrTooLong(256))
        ));
        // F-3: seq > i64::MAX
        let ok = RendezvousRecord {
            overlay_addr: [0; 32],
            endpoints: vec![],
            pq_hint: [0; 32],
            seq: 0,
            valid_until: 0,
        };
        assert!(matches!(
            ok.validate(MAX_SEQ + 1),
            Err(RvError::SeqOutOfRange(_))
        ));
        assert!(ok.validate(MAX_SEQ).is_ok());
        // sign_record rejects oversized before signing
        let sk = dht_signing_key(&derive_dht_seed(&[0x42u8; 64]));
        let salt = derive_salt(&[0x33; 32], 1);
        assert!(sign_record(&sk, &salt, 0, &too_many).is_err());
    }

    #[test]
    fn ssrf_filter_rejects_non_global() {
        // F-2: loopback/private/link-local do not pass the public filter; global does.
        let mk = |a: [u8; 4]| Endpoint {
            kind: EP_DIRECT_V4,
            addr: vec![a[0], a[1], a[2], a[3], 0x20, 0xFC],
        };
        assert!(resolve_endpoint_public(&mk([127, 0, 0, 1])).is_none()); // loopback
        assert!(resolve_endpoint_public(&mk([10, 0, 0, 5])).is_none()); // private
        assert!(resolve_endpoint_public(&mk([192, 168, 1, 1])).is_none()); // private
        assert!(resolve_endpoint_public(&mk([169, 254, 1, 1])).is_none()); // link-local
        assert!(resolve_endpoint_public(&mk([0, 0, 0, 0])).is_none()); // unspecified
        assert!(resolve_endpoint_public(&mk([203, 0, 113, 5])).is_some()); // global
        assert!(resolve_endpoint_public(&mk([100, 64, 0, 1])).is_none()); // CGNAT 100.64/10
                                                                          // IPv4-mapped IPv6 (::ffff:x.x.x.x) used to bypass the filter — now checked by the embedded v4
        let mk6 = |ip: [u8; 16]| Endpoint {
            kind: EP_DIRECT_V6,
            addr: {
                let mut v = ip.to_vec();
                v.extend_from_slice(&[0x20, 0xFC]);
                v
            },
        };
        let mapped = |v4: [u8; 4]| {
            [
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, v4[0], v4[1], v4[2], v4[3],
            ]
        };
        assert!(resolve_endpoint_public(&mk6(mapped([127, 0, 0, 1]))).is_none()); // ::ffff:loopback
        assert!(resolve_endpoint_public(&mk6(mapped([169, 254, 169, 254]))).is_none()); // ::ffff:metadata
        assert!(resolve_endpoint_public(&mk6(mapped([10, 0, 0, 5]))).is_none()); // ::ffff:private
                                                                                 // raw resolve lets loopback through (LAN/self-host are legitimate)
        assert!(resolve_endpoint(&mk([127, 0, 0, 1])).is_some());
    }

    #[test]
    fn record_binds_account_catches_forgery() {
        let account_id = [0x42u8; OVERLAY_ADDR_LEN];
        let record = RendezvousRecord {
            overlay_addr: mt_overlay::overlay_addr(&account_id),
            endpoints: vec![],
            pq_hint: [0u8; PQ_HINT_LEN],
            seq: 1,
            valid_until: 1000,
        };
        assert!(record_binds_account(&record, &account_id)); // legitimate binding
        let mut forged = record.clone();
        forged.overlay_addr = [0xFFu8; OVERLAY_ADDR_LEN];
        assert!(!record_binds_account(&forged, &account_id)); // forged overlay is caught
        assert!(!record_binds_account(&record, &[0x99u8; OVERLAY_ADDR_LEN])); // foreign account
    }
}
