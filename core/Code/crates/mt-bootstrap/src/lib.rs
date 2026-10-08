//! Bootstrap (Montana P2P Network, Stage 5): entering the network from zero knowledge without our
//! server. Byte-exact formats QRBootstrap (QR from a friend) and SeedList (embedded node list,
//! Bitcoin model) + learned-node cache + anchor arbiter. mDNS/BLE/Reality/Snowflake are
//! network/platform layers on top of this core. After the QR endpoint goes stale, the friend's address
//! is resolved via the DHT by dk (Stage 4, mt-rendezvous).

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

use mt_codec::{write_bytes, write_u16, write_u64, write_u8, CanonicalEncode};
use thiserror::Error;

pub const QR_VERSION: u8 = 0x01;
pub const QR_KIND_RELAY_CIRCUIT: u8 = 0x01; // the friend postman's relay-circuit (not a raw socket)
pub const QR_KIND_DIRECT_V6: u8 = 0x02; // direct v6 endpoint (ip16 ‖ port2 BE)
pub const DK_LEN: usize = mt_rendezvous::DK_LEN;

pub const IP_V4: u8 = 0x04;
pub const IP_V6: u8 = 0x06;
/// Minimum bytes per seed (ip_kind 1 + v4 ip 4 + port 2): sanity check before alloc (G-1).
const MIN_SEED_BYTES: usize = 7;
/// Upper bound on deep-link length (QRBootstrap ≤298 B → base64url ≤398 + scheme);
/// protection against a giant link before parsing (G-1 defense-in-depth).
pub const MAX_DEEP_LINK_LEN: usize = 2048;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum BootstrapError {
    #[error("truncated")]
    Truncated,
    #[error("bad version {0:#04x}")]
    BadVersion(u8),
    #[error("bad ep_kind {0:#04x}")]
    BadEpKind(u8),
    #[error("bad ip_kind {0:#04x}")]
    BadIpKind(u8),
    #[error("length mismatch")]
    LengthMismatch,
    #[error("ep too long {0} (max 255)")]
    EpTooLong(usize),
    #[error("base64url: {0}")]
    Base64(&'static str),
    #[error("deep-link: {0}")]
    DeepLink(&'static str),
}

// --- base64url (URL_SAFE_NO_PAD, by hand: no external crate [I-7]) ---

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

pub fn base64url_encode(data: &[u8]) -> String {
    let mut out = String::with_capacity((data.len() + 2) / 3 * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = *chunk.get(1).unwrap_or(&0) as u32;
        let b2 = *chunk.get(2).unwrap_or(&0) as u32;
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(B64[(n >> 18) as usize & 0x3F] as char);
        out.push(B64[(n >> 12) as usize & 0x3F] as char);
        if chunk.len() > 1 {
            out.push(B64[(n >> 6) as usize & 0x3F] as char);
        }
        if chunk.len() > 2 {
            out.push(B64[n as usize & 0x3F] as char);
        }
    }
    out
}

fn b64_val(c: u8) -> Result<u32, BootstrapError> {
    match c {
        b'A'..=b'Z' => Ok((c - b'A') as u32),
        b'a'..=b'z' => Ok((c - b'a' + 26) as u32),
        b'0'..=b'9' => Ok((c - b'0' + 52) as u32),
        b'-' => Ok(62),
        b'_' => Ok(63),
        _ => Err(BootstrapError::Base64("invalid char")),
    }
}

pub fn base64url_decode(s: &str) -> Result<Vec<u8>, BootstrapError> {
    let b = s.as_bytes();
    if b.len() % 4 == 1 {
        return Err(BootstrapError::Base64("bad length"));
    }
    let mut out = Vec::with_capacity(b.len() / 4 * 3);
    for chunk in b.chunks(4) {
        let mut n = 0u32;
        for (i, &c) in chunk.iter().enumerate() {
            n |= b64_val(c)? << (18 - 6 * i);
        }
        out.push((n >> 16) as u8);
        match chunk.len() {
            2 if n & 0x0000_F000 != 0 => return Err(BootstrapError::Base64("overlong")),
            3 if n & 0x0000_00C0 != 0 => return Err(BootstrapError::Base64("overlong")),
            _ => {},
        }
        if chunk.len() > 2 {
            out.push((n >> 8) as u8);
        }
        if chunk.len() > 3 {
            out.push(n as u8);
        }
    }
    Ok(out)
}

// --- QRBootstrap (byte-exact, §607) ---

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct QRBootstrap {
    pub dk: [u8; DK_LEN], // the friend's ed25519 pubkey (Stage 4 admission)
    pub expires: u64,     // endpoint expiry window (unix)
    pub ep_kind: u8,      // 0x01 relay-circuit | 0x02 direct-v6
    pub ep: Vec<u8>,      // the friend's current endpoint
}

impl CanonicalEncode for QRBootstrap {
    fn encode(&self, buf: &mut Vec<u8>) {
        debug_assert!(self.ep.len() <= 255, "ep_len u8 overflow");
        write_u8(buf, QR_VERSION);
        write_bytes(buf, &self.dk);
        write_u64(buf, self.expires);
        write_u8(buf, self.ep_kind);
        write_u8(buf, self.ep.len() as u8);
        write_bytes(buf, &self.ep);
    }
}

impl QRBootstrap {
    pub fn validate(&self) -> Result<(), BootstrapError> {
        if !matches!(self.ep_kind, QR_KIND_RELAY_CIRCUIT | QR_KIND_DIRECT_V6) {
            return Err(BootstrapError::BadEpKind(self.ep_kind));
        }
        if self.ep.len() > 255 {
            return Err(BootstrapError::EpTooLong(self.ep.len()));
        }
        if self.ep_kind == QR_KIND_DIRECT_V6 && self.ep.len() != 18 {
            return Err(BootstrapError::LengthMismatch); // direct-v6 = ip16 ‖ port2
        }
        Ok(())
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = Vec::new();
        self.encode(&mut b);
        b
    }

    pub fn decode(input: &[u8]) -> Result<Self, BootstrapError> {
        // version1 dk32 expires8 ep_kind1 ep_len1 ep
        let min = 1 + DK_LEN + 8 + 1 + 1;
        if input.len() < min {
            return Err(BootstrapError::Truncated);
        }
        if input[0] != QR_VERSION {
            return Err(BootstrapError::BadVersion(input[0]));
        }
        let mut o = 1;
        let mut dk = [0u8; DK_LEN];
        dk.copy_from_slice(&input[o..o + DK_LEN]);
        o += DK_LEN;
        let expires = u64::from_le_bytes(
            input[o..o + 8]
                .try_into()
                .map_err(|_| BootstrapError::Truncated)?,
        );
        o += 8;
        let ep_kind = input[o];
        if !matches!(ep_kind, QR_KIND_RELAY_CIRCUIT | QR_KIND_DIRECT_V6) {
            return Err(BootstrapError::BadEpKind(ep_kind));
        }
        let ep_len = input[o + 1] as usize;
        o += 2;
        if input.len() != o + ep_len {
            return Err(BootstrapError::LengthMismatch);
        }
        let ep = input[o..o + ep_len].to_vec();
        Ok(Self {
            dk,
            expires,
            ep_kind,
            ep,
        })
    }

    /// QR string (base64url of the body). The scanner calls from_qr.
    pub fn to_qr(&self) -> String {
        base64url_encode(&self.to_bytes())
    }

    pub fn from_qr(s: &str) -> Result<Self, BootstrapError> {
        Self::decode(&base64url_decode(s)?)
    }

    /// Current direct endpoint, if the QR is not stale (now < expires) and it is direct-v6.
    /// Otherwise None: the caller resolves the friend's address via the DHT by dk (Stage 4, §618).
    /// relay-circuit does not resolve to a raw socket (it goes through the overlay layer).
    pub fn current_endpoint(&self, now_unix: u64) -> Option<SocketAddr> {
        if now_unix >= self.expires {
            return None;
        }
        if self.ep_kind == QR_KIND_DIRECT_V6 && self.ep.len() == 18 {
            let mut a = [0u8; 16];
            a.copy_from_slice(&self.ep[..16]);
            let port = u16::from_be_bytes([self.ep[16], self.ep[17]]);
            return Some(SocketAddr::new(IpAddr::V6(Ipv6Addr::from(a)), port));
        }
        None
    }

    /// Like current_endpoint, but lets through only a globally routable address
    /// (B-1: an untrusted deep-link QR will not point the node at an internal network: SSRF).
    /// A friend's physical QR on a LAN uses the raw current_endpoint. SSOT filter from Stage 4.
    pub fn current_endpoint_public(&self, now_unix: u64) -> Option<SocketAddr> {
        self.current_endpoint(now_unix)
            .filter(mt_rendezvous::is_global_unicast)
    }
}

// --- Deep-link montana:// --- Deep-link montana:// (variant A, §613) ---

pub const DEEP_LINK_SCHEME: &str = "montana://";

/// Parsed invitation link. Bootstrap carries the QRBootstrap itself (offline);
/// Address is the friend's public wallet address (identity = mt-address, not a fake @-domain),
/// resolved by the caller: mt-address → account_id → overlay_addr → DHT rendezvous (Stage 4).
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum DeepLink {
    Bootstrap(QRBootstrap),
    Address(String), // "mt" ‖ base58(account_id ‖ checksum)
}

// Bitcoin base58 (without 0 O I l).
fn is_base58_char(c: u8) -> bool {
    matches!(c, b'1'..=b'9' | b'A'..=b'H' | b'J'..=b'N' | b'P'..=b'Z' | b'a'..=b'k' | b'm'..=b'z')
}

impl QRBootstrap {
    /// Clickable invitation link montana://b/<base64url(QRBootstrap)>: the payload
    /// is identical to the QR, the scheme is not resolved via DNS (data is inside the link).
    pub fn to_deep_link(&self) -> String {
        format!("{}b/{}", DEEP_LINK_SCHEME, self.to_qr())
    }
}

/// Parse a montana:// link. montana://b/<...> → Bootstrap; montana://<mt-address> → Address.
pub fn parse_deep_link(s: &str) -> Result<DeepLink, BootstrapError> {
    if s.len() > MAX_DEEP_LINK_LEN {
        return Err(BootstrapError::DeepLink("too long"));
    }
    let rest = s
        .strip_prefix(DEEP_LINK_SCHEME)
        .ok_or(BootstrapError::DeepLink("scheme != montana://"))?;
    if let Some(payload) = rest.strip_prefix("b/") {
        return Ok(DeepLink::Bootstrap(QRBootstrap::from_qr(payload)?));
    }
    // montana:// montana://<mt-address>: mt prefix + non-empty base58 body
    if let Some(body) = rest.strip_prefix("mt") {
        if !body.is_empty() && body.bytes().all(is_base58_char) {
            return Ok(DeepLink::Address(rest.to_string()));
        }
        return Err(BootstrapError::DeepLink("malformed mt-address"));
    }
    Err(BootstrapError::DeepLink("unknown deep-link body"))
}

// --- SeedList (byte-exact, §622) + learned-node cache ---
// Versioning: deliberately no version byte. Shipped in the binary and updated
// with it (both sides are version-synchronous via bump); QRBootstrap is versioned
// separately, as it is long-lived and cross-version (a QR/link from a friend to an old client).

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Seed {
    pub ip_kind: u8, // 0x04 v4 | 0x06 v6
    pub ip: Vec<u8>, // 4 | 16
    pub port: u16,
}

impl Seed {
    pub fn from_socket(addr: SocketAddr) -> Self {
        match addr.ip() {
            IpAddr::V4(v4) => Seed {
                ip_kind: IP_V4,
                ip: v4.octets().to_vec(),
                port: addr.port(),
            },
            IpAddr::V6(v6) => Seed {
                ip_kind: IP_V6,
                ip: v6.octets().to_vec(),
                port: addr.port(),
            },
        }
    }

    pub fn to_socket(&self) -> Option<SocketAddr> {
        match (self.ip_kind, self.ip.len()) {
            (IP_V4, 4) => {
                let ip = Ipv4Addr::new(self.ip[0], self.ip[1], self.ip[2], self.ip[3]);
                Some(SocketAddr::new(IpAddr::V4(ip), self.port))
            },
            (IP_V6, 16) => {
                let mut a = [0u8; 16];
                a.copy_from_slice(&self.ip);
                Some(SocketAddr::new(IpAddr::V6(Ipv6Addr::from(a)), self.port))
            },
            _ => None,
        }
    }
}

#[derive(Clone, PartialEq, Eq, Debug, Default)]
pub struct SeedList {
    pub seeds: Vec<Seed>,
}

impl CanonicalEncode for SeedList {
    fn encode(&self, buf: &mut Vec<u8>) {
        debug_assert!(self.seeds.len() <= u16::MAX as usize, "count u16 overflow");
        write_u16(buf, self.seeds.len() as u16);
        for s in &self.seeds {
            write_u8(buf, s.ip_kind);
            write_bytes(buf, &s.ip);
            // port is network byte order (BE), consistent with Stage 4 resolve_endpoint
            write_bytes(buf, &s.port.to_be_bytes());
        }
    }
}

impl SeedList {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = Vec::new();
        self.encode(&mut b);
        b
    }

    pub fn decode(input: &[u8]) -> Result<Self, BootstrapError> {
        if input.len() < 2 {
            return Err(BootstrapError::Truncated);
        }
        let count = u16::from_le_bytes([input[0], input[1]]) as usize;
        // G-1: do not reserve memory for a counter not backed by data.
        if input.len() - 2 < count * MIN_SEED_BYTES {
            return Err(BootstrapError::Truncated);
        }
        let mut o = 2;
        let mut seeds = Vec::with_capacity(count);
        for _ in 0..count {
            if input.len() < o + 1 {
                return Err(BootstrapError::Truncated);
            }
            let ip_kind = input[o];
            let ip_len = match ip_kind {
                IP_V4 => 4,
                IP_V6 => 16,
                _ => return Err(BootstrapError::BadIpKind(ip_kind)),
            };
            o += 1;
            if input.len() < o + ip_len + 2 {
                return Err(BootstrapError::Truncated);
            }
            let ip = input[o..o + ip_len].to_vec();
            o += ip_len;
            let port = u16::from_be_bytes([input[o], input[o + 1]]);
            o += 2;
            seeds.push(Seed { ip_kind, ip, port });
        }
        if o != input.len() {
            return Err(BootstrapError::LengthMismatch);
        }
        Ok(Self { seeds })
    }

    /// Learned-node cache on disk: reuses the SeedList format (SSOT).
    pub fn save(&self, path: &std::path::Path) -> std::io::Result<()> {
        std::fs::write(path, self.to_bytes())
    }

    pub fn load(path: &std::path::Path) -> std::io::Result<Self> {
        let bytes = std::fs::read(path)?;
        Self::decode(&bytes).map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
    }
}

// --- Anchor arbiter (§605: local first) ---

/// Ordered candidate addresses for entry: learned-node cache (fresh, §605-3) →
/// the friend's direct QR endpoint (§605-2, if not stale) → embedded seed list (§605-3).
/// mDNS/BLE (§605-1) and Reality/Snowflake (§605-5/6) are network layers above the core.
/// Dedup preserving priority order.
pub fn bootstrap_targets(
    qr: Option<&QRBootstrap>,
    cache: &SeedList,
    embedded: &SeedList,
    now_unix: u64,
) -> Vec<SocketAddr> {
    let mut out: Vec<SocketAddr> = Vec::new();
    let push = |a: SocketAddr, out: &mut Vec<SocketAddr>| {
        if !out.contains(&a) {
            out.push(a);
        }
    };
    for s in &cache.seeds {
        if let Some(a) = s.to_socket() {
            push(a, &mut out);
        }
    }
    if let Some(qr) = qr {
        // qr comes from an untrusted deep-link montana://b/ — filter through the
        // SSRF predicate (C-6: otherwise a direct-v6 to an internal address makes the node dial
        // into the internal network). Physical LAN exchange goes via the Stage 6 mDNS path, not here.
        if let Some(a) = qr.current_endpoint_public(now_unix) {
            push(a, &mut out);
        }
    }
    for s in &embedded.seeds {
        if let Some(a) = s.to_socket() {
            push(a, &mut out);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64url_roundtrip_all_remainders() {
        for len in 0..12usize {
            let data: Vec<u8> = (0..len as u8).collect();
            let enc = base64url_encode(&data);
            assert!(!enc.contains('='), "no padding");
            assert_eq!(base64url_decode(&enc).unwrap(), data, "len={len}");
        }
        // KAT (Pass 25): RFC 4648 base64url without padding
        assert_eq!(base64url_encode(b""), "");
        assert_eq!(base64url_encode(b"f"), "Zg");
        assert_eq!(base64url_encode(b"fo"), "Zm8");
        assert_eq!(base64url_encode(b"foo"), "Zm9v");
        assert_eq!(base64url_encode(b"foob"), "Zm9vYg");
        assert_eq!(base64url_encode(&[0xFB, 0xFF]), "-_8"); // checks - and _
    }

    #[test]
    fn base64url_rejects_bad() {
        assert!(base64url_decode("A").is_err()); // len%4==1
        assert!(base64url_decode("Zm9v+g").is_err()); // + is not url-safe
        assert!(base64url_decode("ab/c").is_err()); // / is not url-safe
    }

    fn sample_qr() -> QRBootstrap {
        let mut ep = vec![0u8; 16];
        ep[15] = 1;
        ep.extend_from_slice(&8444u16.to_be_bytes());
        QRBootstrap {
            dk: [0xAB; 32],
            expires: 2_000_000,
            ep_kind: QR_KIND_DIRECT_V6,
            ep,
        }
    }

    #[test]
    fn byte_layout_kat_oracle() {
        // Pass 25: independent python oracle (struct/base64): cross-client byte-exact.
        let q = sample_qr();
        assert_eq!(
            hex::encode(q.to_bytes()),
            "01abababababababababababababababababababababababababababababababab80841e000000000002120000000000000000000000000000000120fc"
        );
        assert_eq!(
            q.to_qr(),
            "Aaurq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urgIQeAAAAAAACEgAAAAAAAAAAAAAAAAAAAAEg_A"
        );
        let sl = SeedList {
            seeds: vec![
                Seed {
                    ip_kind: IP_V4,
                    ip: vec![203, 0, 113, 7],
                    port: 8444,
                },
                Seed {
                    ip_kind: IP_V6,
                    ip: {
                        let mut a = vec![0u8; 16];
                        a[15] = 1;
                        a
                    },
                    port: 9000,
                },
            ],
        };
        assert_eq!(
            hex::encode(sl.to_bytes()),
            "020004cb00710720fc06000000000000000000000000000000012328"
        );
    }

    #[test]
    fn ssrf_public_filter_and_overlong_base64() {
        // B-1: an untrusted QR on loopback/internal does not pass the public filter.
        let mk = |seg15: u8| QRBootstrap {
            dk: [0; 32],
            expires: 1000,
            ep_kind: QR_KIND_DIRECT_V6,
            ep: {
                let mut e = vec![0u8; 16];
                e[15] = seg15;
                e.extend_from_slice(&80u16.to_be_bytes());
                e
            },
        };
        // ::1 = loopback → public rejects, raw lets through (LAN)
        assert!(mk(1).current_endpoint_public(0).is_none());
        assert!(mk(1).current_endpoint(0).is_some());
        // B-3: overlong base64url (non-zero trailing bits) is rejected
        assert!(base64url_decode("Zh").is_err()); // "Zg"=[0x66]; "Zh" overlong
        assert_eq!(base64url_decode("Zg").unwrap(), vec![0x66]);
        // B-4: direct-v6 with ep.len != 18 is invalid
        let bad = QRBootstrap {
            dk: [0; 32],
            expires: 0,
            ep_kind: QR_KIND_DIRECT_V6,
            ep: vec![1, 2, 3],
        };
        assert_eq!(bad.validate(), Err(BootstrapError::LengthMismatch));
    }

    #[test]
    fn qr_roundtrip_and_qr_string() {
        let q = sample_qr();
        assert_eq!(QRBootstrap::decode(&q.to_bytes()).unwrap(), q);
        assert_eq!(QRBootstrap::from_qr(&q.to_qr()).unwrap(), q);
    }

    #[test]
    fn qr_rejects_bad_version_kind_and_tail() {
        let q = sample_qr();
        let mut b = q.to_bytes();
        b[0] = 0x02; // version
        assert!(matches!(
            QRBootstrap::decode(&b),
            Err(BootstrapError::BadVersion(0x02))
        ));
        let mut b2 = q.to_bytes();
        b2[41] = 0x09; // ep_kind (1+32+8=41)
        assert!(matches!(
            QRBootstrap::decode(&b2),
            Err(BootstrapError::BadEpKind(0x09))
        ));
        let mut b3 = q.to_bytes();
        b3.push(0x00); // extra tail
        assert_eq!(
            QRBootstrap::decode(&b3),
            Err(BootstrapError::LengthMismatch)
        );
    }

    #[test]
    fn qr_expires_gates_endpoint() {
        let q = sample_qr(); // expires=2_000_000, direct-v6 [::1]:8444
        assert_eq!(
            q.current_endpoint(1_000_000).unwrap().to_string(),
            "[::1]:8444"
        );
        assert!(q.current_endpoint(2_000_000).is_none(), "stale → DHT path");
        // relay-circuit does not resolve to a socket
        let relay = QRBootstrap {
            ep_kind: QR_KIND_RELAY_CIRCUIT,
            ep: vec![1, 2, 3],
            ..q
        };
        assert!(relay.current_endpoint(0).is_none());
    }

    #[test]
    fn seedlist_roundtrip_v4_v6_and_socket() {
        let list = SeedList {
            seeds: vec![
                Seed {
                    ip_kind: IP_V4,
                    ip: vec![203, 0, 113, 7],
                    port: 8444,
                },
                Seed {
                    ip_kind: IP_V6,
                    ip: {
                        let mut a = vec![0u8; 16];
                        a[15] = 1;
                        a
                    },
                    port: 9000,
                },
            ],
        };
        assert_eq!(SeedList::decode(&list.to_bytes()).unwrap(), list);
        assert_eq!(
            list.seeds[0].to_socket().unwrap().to_string(),
            "203.0.113.7:8444"
        );
        assert_eq!(list.seeds[1].to_socket().unwrap().to_string(), "[::1]:9000");
        // roundtrip via SocketAddr
        let a: SocketAddr = "203.0.113.7:8444".parse().unwrap();
        assert_eq!(Seed::from_socket(a).to_socket().unwrap(), a);
    }

    #[test]
    fn seedlist_rejects_bad_ipkind_and_tail() {
        let list = SeedList {
            seeds: vec![Seed {
                ip_kind: IP_V4,
                ip: vec![1, 2, 3, 4],
                port: 1,
            }],
        };
        let mut b = list.to_bytes();
        b[2] = 0x05; // ip_kind
        assert!(matches!(
            SeedList::decode(&b),
            Err(BootstrapError::BadIpKind(0x05))
        ));
        let mut b2 = list.to_bytes();
        b2.push(0xFF);
        assert_eq!(SeedList::decode(&b2), Err(BootstrapError::LengthMismatch));
        // empty list
        let empty = SeedList::default();
        assert_eq!(SeedList::decode(&empty.to_bytes()).unwrap(), empty);
    }

    #[test]
    fn arbiter_orders_cache_qr_embedded_dedup() {
        let cache = SeedList {
            seeds: vec![Seed {
                ip_kind: IP_V4,
                ip: vec![10, 0, 0, 1],
                port: 1,
            }],
        };
        let embedded = SeedList {
            seeds: vec![
                Seed {
                    ip_kind: IP_V4,
                    ip: vec![10, 0, 0, 1],
                    port: 1,
                }, // duplicate of the cache
                Seed {
                    ip_kind: IP_V4,
                    ip: vec![203, 0, 113, 9],
                    port: 2,
                },
            ],
        };
        let q = sample_qr(); // direct-v6 [::1]:8444 (loopback: untrusted QR)
        let targets = bootstrap_targets(Some(&q), &cache, &embedded, 1_000_000);
        // C-6: the QR endpoint [::1] (loopback from an untrusted deep-link) is filtered by the
        // SSRF predicate; the trusted cache + embedded entries remain.
        assert_eq!(targets.len(), 2);
        assert_eq!(targets[0].to_string(), "10.0.0.1:1"); // cache (trusted, not filtered)
        assert_eq!(targets[1].to_string(), "203.0.113.9:2"); // embedded
        assert!(
            !targets.iter().any(|t| t.to_string() == "[::1]:8444"),
            "loopback QR is not in targets (SSRF)"
        );
        // a stale QR also drops out
        let targets2 = bootstrap_targets(Some(&q), &cache, &embedded, 3_000_000);
        assert_eq!(targets2.len(), 2);
    }

    #[test]
    fn g1_rejects_amplification_and_oversized_link() {
        // G-1: count=65535 with 2 bytes of data → Truncated BEFORE reserving memory.
        let evil = 65535u16.to_le_bytes().to_vec();
        assert_eq!(SeedList::decode(&evil), Err(BootstrapError::Truncated));
        // a giant deep-link is rejected by length
        let huge = format!("montana://b/{}", "A".repeat(MAX_DEEP_LINK_LEN));
        assert!(matches!(
            parse_deep_link(&huge),
            Err(BootstrapError::DeepLink(_))
        ));
    }

    #[test]
    fn deep_link_bootstrap_roundtrip() {
        let q = sample_qr();
        let link = q.to_deep_link();
        assert!(link.starts_with("montana://b/"));
        assert_eq!(parse_deep_link(&link).unwrap(), DeepLink::Bootstrap(q));
    }

    #[test]
    fn deep_link_address_and_rejects() {
        // montana:// montana://<mt-address> → Address (identity = wallet)
        let addr = "mt1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2";
        assert_eq!(
            parse_deep_link(&format!("montana://{addr}")).unwrap(),
            DeepLink::Address(addr.to_string())
        );
        // foreign scheme
        assert!(matches!(
            parse_deep_link("https://evil/x"),
            Err(BootstrapError::DeepLink(_))
        ));
        // mt-address with an invalid base58 character (0 O I l)
        assert!(parse_deep_link("montana://mt0OIl").is_err());
        // empty body
        assert!(parse_deep_link("montana://").is_err());
        // neither mt nor b/
        assert!(parse_deep_link("montana://xyz").is_err());
    }
}
