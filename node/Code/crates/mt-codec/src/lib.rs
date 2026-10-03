#![no_std]

extern crate alloc;

use alloc::vec::Vec;

// spec, раздел "Consensus encoding layer"

pub trait CanonicalEncode {
    fn encode(&self, buf: &mut Vec<u8>);
}

#[inline]
pub fn write_u8(buf: &mut Vec<u8>, v: u8) {
    buf.push(v);
}

#[inline]
pub fn write_u16(buf: &mut Vec<u8>, v: u16) {
    buf.extend_from_slice(&v.to_le_bytes());
}

#[inline]
pub fn write_u32(buf: &mut Vec<u8>, v: u32) {
    buf.extend_from_slice(&v.to_le_bytes());
}

#[inline]
pub fn write_u64(buf: &mut Vec<u8>, v: u64) {
    buf.extend_from_slice(&v.to_le_bytes());
}

#[inline]
pub fn write_u128(buf: &mut Vec<u8>, v: u128) {
    buf.extend_from_slice(&v.to_le_bytes());
}

#[inline]
pub fn write_bytes(buf: &mut Vec<u8>, v: &[u8]) {
    buf.extend_from_slice(v);
}

// spec, раздел "Domain separators registry"
pub mod domain {
    // Class domains (Правило R2 — identifier(obj))
    pub const OP: &[u8] = b"mt-op";
    pub const NODEREG: &[u8] = b"mt-nodereg";
    pub const PROPOSAL: &[u8] = b"mt-proposal";
    pub const BUNDLE: &[u8] = b"mt-bundle";
    pub const SSHA_REVEAL: &[u8] = b"mt-ssha-reveal";

    // Account/Node derivation
    pub const ACCOUNT: &[u8] = b"mt-account";
    pub const CANDIDATE_SSHA_INIT: &[u8] = b"mt-candidate-ssha-init";
    pub const MERKLE_LEAF: &[u8] = b"mt-merkle-leaf";
    pub const MERKLE_NODE: &[u8] = b"mt-merkle-node";
    pub const STATE_ROOT: &[u8] = b"mt-state-root";
    pub const TIMECHAIN: &[u8] = b"mt-timechain";
    pub const LOTTERY: &[u8] = b"mt-lottery";
    pub const BC_AGGREGATE: &[u8] = b"mt-bc-aggregate";
    pub const BC_AGGREGATE_EMPTY: &[u8] = b"mt-bc-aggregate-empty";
    pub const SELECTION: &[u8] = b"mt-selection";
    pub const NODEREG_SORT: &[u8] = b"mt-nodereg-sort";
    pub const CONFIRMATION: &[u8] = b"mt-confirmation";
    pub const APP: &[u8] = b"mt-app";
    pub const NODE: &[u8] = b"mt-node";
    pub const GENESIS: &[u8] = b"mt-genesis";
    pub const SEED: &[u8] = b"mt-seed";
    // Смешивание независимых источников в корень личности: доверие не должно
    // сходиться в одну точку, и ни один источник не обязан быть хорошим в одиночку.
    pub const ENTROPY_MIX: &[u8] = b"mt-entropy-mix";
    pub const ACCOUNT_KEY: &[u8] = b"mt-account-key";
    pub const NODE_KEY: &[u8] = b"mt-node-key";
    pub const CONTENT_CHUNK: &[u8] = b"mt-content-chunk";
    pub const CONTENT_MANIFEST: &[u8] = b"mt-content-manifest";
    pub const PROFILE: &[u8] = b"mt-profile";
    pub const ENCRYPTION_KEY: &[u8] = b"mt-encryption-key";
    pub const APP_ENCRYPTION_KEY: &[u8] = b"mt-app-encryption-key";
    pub const PREKEYS: &[u8] = b"mt-prekeys";
    // [I-16] admission A-1 (Classical-only-as-admission): ed25519 здесь — admission-
    // обёртка libp2p PeerId, НЕ Montana-security. libp2p PeerId (транспортная
    // адресация M8 cross-machine). Ed25519 навязан
    // libp2p-машинерией PeerId (ML-DSA не стандартный libp2p key type), как BEP44
    // навязывает Ed25519 — scoped-исключение. НЕ несёт крипто-аутентификацию:
    // подлинность пира постквантовая — ML-DSA-65 подпись transcript в Noise_PQ XX
    // (mt-noise-pq), DH через ML-KEM-768. Derived из master_seed (Mode A recoverable)
    // либо ephemeral в identity.bin (Mode B).
    pub const LIBP2P_TRANSPORT_KEY: &[u8] = b"mt-libp2p-transport-key";
    pub const TUNNEL_ONLINE: &[u8] = b"mt-tunnel-online";
    pub const TUNNEL_MESH: &[u8] = b"mt-tunnel-mesh";
    // P2P-сеть (Montana P2P Network, Этап 1): оверлей-адрес узла из account_id.
    pub const OVERLAY: &[u8] = b"mt-overlay";
    // P2P-сеть: op-домены challenge-response владения (регистрация / fetch инбокса).
    pub const OVERLAY_REG: &[u8] = b"mt-reg";
    pub const OVERLAY_FETCH: &[u8] = b"mt-fetch";
    // P2P Этап 2: вращающийся тег инбокса store-and-forward (из account_id + окна).
    // (устаревает Montana Unlinkable Queues, но домен сохраняется для истории/совместимости)
    pub const INBOX_TAG: &[u8] = b"mt-inbox-tag";
    // P2P Этап 2 (MUQ): unlinkable queues — раздельные send_id/recv_id.
    pub const QUEUE_RECV: &[u8] = b"mt-queue-recv"; // деривация эфемерного recv_key очереди (M-1)
    pub const QUEUE_SEND: &[u8] = b"mt-queue-send"; // secured-депозит + деривация send_key (M-1)
    pub const QUEUE_SUB: &[u8] = b"mt-queue-sub"; // подпись выборки (recv_key)
    pub const QUEUE_ROT: &[u8] = b"mt-queue-rot"; // согласование ротации в храповике
    pub const QUEUE_INBOX: &[u8] = b"mt-queue-inbox"; // opt-in первый контакт (отдельно от mt-inbox)
    pub const DHT_KEY: &[u8] = b"mt-dht-key"; // HKDF-ветка ed25519 dht_key (BEP44 admission, [P2P-5]/A-2)
    pub const RV_SALT: &[u8] = b"mt-rv-salt"; // деривация BEP44 salt рандеву-записи
                                              // TLS-Exporter label для channel-binding challenge-response (RFC 8446 §7.5) — не hash-domain.
    pub const OVERLAY_CHANNEL_LABEL: &[u8] = b"mt-overlay-channel";
    pub const RECOVERY_FINGERPRINT: &[u8] = b"mt-recovery-fingerprint";
    // Мессенджер-слой (Montana Messenger v0.49). Канонический источник доменных строк
    // identity-binding / auth / истории — клиенты (iOS MontanaDomain, Web) зеркалят отсюда.
    pub const MSG_IDKEM: &[u8] = b"mt-idkem"; // подпись app_kem_pub ключом account_key (Этап 4/5)
    pub const MSG_PREKEY: &[u8] = b"mt-prekey"; // подпись signed_prekey
    pub const MSG_AUTH: &[u8] = b"mt-auth"; // подпись сессионного nonce (Этап 2)
    pub const MSG_HISTORY_KEY: &[u8] = b"mt-history-key"; // HKDF info для history_key (Этап 10)
    pub const MSG_HISTORY: &[u8] = b"mt-history"; // AD блоков истории (Этап 10)
    pub const MSG_HISTORY_WRITER: &[u8] = b"mt-history-writer"; // writer_tag = SHA-256(dom‖0x00‖device_id)[0:4] (s.2 St.1)
    pub const MSG_MSG_LEAF: &[u8] = b"mt-msg-leaf"; // ArchiveRoot leaf (s.2 St.2)
    pub const MSG_MSG_NODE: &[u8] = b"mt-msg-node"; // ArchiveRoot node (s.2 St.2)
    pub const MSG_ARCHIVE_SYNC: &[u8] = b"mt-archive-sync"; // ArchiveSyncRequest sig (s.2 St.3)
    pub const MSG_RECOVER_REQ: &[u8] = b"mt-recover-req"; // RecoveryRequest sig (s.2 St.6)
    pub const MSG_COMPACT: &[u8] = b"mt-compact"; // CompactionManifest sig (s.2 St.10)
    pub const MSG_MEDIA_KEY: &[u8] = b"mt-media-key"; // HKDF info для media_key (s.2 Этап 1)
    pub const MSG_MEDIA_VAULT: &[u8] = b"mt-media-vault"; // AD медиа at-rest vault (s.2 Этап 1)
    pub const MSG_DEVICE_LINK: &[u8] = b"montana-link"; // обёртка ключа при QR-привязке устройства
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    #[test]
    fn write_u8_single_byte() {
        let mut buf = Vec::new();
        write_u8(&mut buf, 0xAB);
        assert_eq!(buf, vec![0xAB]);
    }

    #[test]
    fn write_u16_little_endian() {
        let mut buf = Vec::new();
        write_u16(&mut buf, 0x1234);
        assert_eq!(buf, vec![0x34, 0x12]);
    }

    #[test]
    fn write_u32_little_endian() {
        let mut buf = Vec::new();
        write_u32(&mut buf, 0xDEADBEEF);
        assert_eq!(buf, vec![0xEF, 0xBE, 0xAD, 0xDE]);
    }

    #[test]
    fn write_u64_one() {
        let mut buf = Vec::new();
        write_u64(&mut buf, 1);
        assert_eq!(buf, vec![0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    }

    #[test]
    fn write_u64_max() {
        let mut buf = Vec::new();
        write_u64(&mut buf, u64::MAX);
        assert_eq!(buf, vec![0xFF; 8]);
    }

    #[test]
    fn write_u128_emission_moneta() {
        // spec: EMISSION_moneta = 13_000_000_000
        let mut buf = Vec::new();
        write_u128(&mut buf, 13_000_000_000u128);
        let expected = 13_000_000_000u128.to_le_bytes();
        assert_eq!(buf.as_slice(), &expected);
        assert_eq!(buf.len(), 16);
    }

    #[test]
    fn write_bytes_raw_no_prefix() {
        let mut buf = Vec::new();
        write_bytes(&mut buf, &[0xAA, 0xBB, 0xCC]);
        assert_eq!(buf, vec![0xAA, 0xBB, 0xCC]);
    }

    #[test]
    fn write_bytes_empty() {
        let mut buf = Vec::new();
        write_bytes(&mut buf, &[]);
        assert!(buf.is_empty());
    }

    #[test]
    fn multiple_writes_concat() {
        let mut buf = Vec::new();
        write_u8(&mut buf, 0x01);
        write_u16(&mut buf, 0x0302);
        write_u32(&mut buf, 0x07060504);
        assert_eq!(buf, vec![0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]);
    }

    #[test]
    fn domain_lottery_ascii() {
        // spec: "mt-lottery" → 10 bytes 0x6D 0x74 0x2D 0x6C 0x6F 0x74 0x74 0x65 0x72 0x79
        assert_eq!(
            domain::LOTTERY,
            &[0x6D, 0x74, 0x2D, 0x6C, 0x6F, 0x74, 0x74, 0x65, 0x72, 0x79]
        );
    }

    #[test]
    fn domain_account_ascii() {
        assert_eq!(domain::ACCOUNT, b"mt-account");
        assert_eq!(domain::ACCOUNT.len(), 10);
    }

    #[test]
    fn domain_class_domains_ascii() {
        assert_eq!(domain::OP, b"mt-op");
        assert_eq!(domain::NODEREG, b"mt-nodereg");
        assert_eq!(domain::PROPOSAL, b"mt-proposal");
        assert_eq!(domain::BUNDLE, b"mt-bundle");
        assert_eq!(domain::SSHA_REVEAL, b"mt-ssha-reveal");
    }

    #[test]
    fn domain_node_ascii() {
        assert_eq!(domain::NODE, b"mt-node");
    }

    #[test]
    fn domain_state_root_ascii() {
        assert_eq!(domain::STATE_ROOT, b"mt-state-root");
    }

    #[test]
    fn domain_merkle_leaf_ascii() {
        assert_eq!(domain::MERKLE_LEAF, b"mt-merkle-leaf");
    }

    #[test]
    fn domain_merkle_node_ascii() {
        assert_eq!(domain::MERKLE_NODE, b"mt-merkle-node");
    }

    #[test]
    fn domain_timechain_ascii() {
        assert_eq!(domain::TIMECHAIN, b"mt-timechain");
    }

    #[test]
    fn domain_selection_ascii() {
        assert_eq!(domain::SELECTION, b"mt-selection");
    }

    #[test]
    fn domain_bc_aggregate_ascii() {
        assert_eq!(domain::BC_AGGREGATE, b"mt-bc-aggregate");
        assert_eq!(domain::BC_AGGREGATE_EMPTY, b"mt-bc-aggregate-empty");
    }

    #[test]
    fn domain_nodereg_sort_ascii() {
        assert_eq!(domain::NODEREG_SORT, b"mt-nodereg-sort");
    }

    #[test]
    fn domain_candidate_ssha_init_ascii() {
        assert_eq!(domain::CANDIDATE_SSHA_INIT, b"mt-candidate-ssha-init");
    }

    #[test]
    fn domain_tunnel_online_ascii() {
        assert_eq!(domain::TUNNEL_ONLINE, b"mt-tunnel-online");
    }

    #[test]
    fn domain_tunnel_mesh_ascii() {
        assert_eq!(domain::TUNNEL_MESH, b"mt-tunnel-mesh");
    }

    #[test]
    fn domain_tunnel_prefix_free() {
        assert!(!domain::TUNNEL_MESH.starts_with(domain::TUNNEL_ONLINE));
        assert!(!domain::TUNNEL_ONLINE.starts_with(domain::TUNNEL_MESH));
    }

    #[test]
    fn domain_recovery_fingerprint_ascii() {
        assert_eq!(domain::RECOVERY_FINGERPRINT, b"mt-recovery-fingerprint");
    }

    #[test]
    fn all_domains_start_with_mt_dash() {
        let all: [&[u8]; 32] = [
            domain::OP,
            domain::NODEREG,
            domain::PROPOSAL,
            domain::BUNDLE,
            domain::SSHA_REVEAL,
            domain::ACCOUNT,
            domain::CANDIDATE_SSHA_INIT,
            domain::MERKLE_LEAF,
            domain::MERKLE_NODE,
            domain::STATE_ROOT,
            domain::TIMECHAIN,
            domain::LOTTERY,
            domain::BC_AGGREGATE,
            domain::BC_AGGREGATE_EMPTY,
            domain::SELECTION,
            domain::NODEREG_SORT,
            domain::CONFIRMATION,
            domain::APP,
            domain::NODE,
            domain::GENESIS,
            domain::SEED,
            domain::ACCOUNT_KEY,
            domain::NODE_KEY,
            domain::CONTENT_CHUNK,
            domain::CONTENT_MANIFEST,
            domain::PROFILE,
            domain::ENCRYPTION_KEY,
            domain::APP_ENCRYPTION_KEY,
            domain::PREKEYS,
            domain::TUNNEL_ONLINE,
            domain::TUNNEL_MESH,
            domain::RECOVERY_FINGERPRINT,
        ];
        for d in all {
            assert!(
                d.starts_with(b"mt-"),
                "domain does not start with mt-: {d:?}"
            );
        }
        assert_eq!(all.len(), 32);
    }

    // Property-style test: write → read roundtrip for 1000 deterministic u64 values.
    // Uses xorshift PRNG to avoid external crate dependency.
    #[test]
    fn roundtrip_u64_property() {
        let mut state: u64 = 0x9E3779B97F4A7C15; // SplitMix64 golden gamma
        for _ in 0..1000 {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            let original = state;

            let mut buf = Vec::new();
            write_u64(&mut buf, original);
            assert_eq!(buf.len(), 8);
            let mut arr = [0u8; 8];
            arr.copy_from_slice(&buf);
            let roundtripped = u64::from_le_bytes(arr);
            assert_eq!(roundtripped, original);
        }
    }

    #[test]
    fn roundtrip_u128_property() {
        let mut lo: u64 = 0xDEADBEEFCAFEBABE;
        let mut hi: u64 = 0x1234567890ABCDEF;
        for _ in 0..1000 {
            lo ^= lo << 13;
            lo ^= lo >> 7;
            lo ^= lo << 17;
            hi ^= hi << 11;
            hi ^= hi >> 5;
            hi ^= hi << 23;
            let original = ((hi as u128) << 64) | (lo as u128);

            let mut buf = Vec::new();
            write_u128(&mut buf, original);
            assert_eq!(buf.len(), 16);
            let mut arr = [0u8; 16];
            arr.copy_from_slice(&buf);
            let roundtripped = u128::from_le_bytes(arr);
            assert_eq!(roundtripped, original);
        }
    }

    #[test]
    fn canonical_encode_trait_works() {
        struct Pair {
            a: u32,
            b: u16,
        }
        impl CanonicalEncode for Pair {
            fn encode(&self, buf: &mut Vec<u8>) {
                write_u32(buf, self.a);
                write_u16(buf, self.b);
            }
        }
        let p = Pair {
            a: 0x01020304,
            b: 0x0506,
        };
        let mut buf = Vec::new();
        p.encode(&mut buf);
        assert_eq!(buf, vec![0x04, 0x03, 0x02, 0x01, 0x06, 0x05]);
    }
}
