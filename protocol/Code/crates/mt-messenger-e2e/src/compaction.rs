//! Stage 10 (second front) — history compaction: the old HistoryBlock log moves into cold sealed blobs,
//! the active log stays bounded, and the cold part's verifiability is preserved through the anchor.
//!
//! CompactionManifest (3414 B):
//!   format 1 (=0x01) ‖ compacted_up_to_seq u64 LE ‖ cold_blob_id 32 ‖ cold_blob_key 32 ‖ cold_root 32
//!   ‖ sig 3309   (ML-DSA-65 account_key over "mt-compact" ‖ 0x00 ‖ format ‖ compacted_up_to_seq
//!                 ‖ cold_blob_id ‖ cold_blob_key ‖ cold_root — 116 B).
//! cold_root = Merkle root of exactly the blocks [0..compacted_up_to_seq); it folds into the anchor
//! ArchiveRoot (Stage 2), so the cold part stays provable.

use crate::crypto::{dsa_sign, dsa_verify, MLDSA_SIG};
use crate::merkle::archive_root;
use mt_codec::domain::MSG_COMPACT;

pub const COMPACT_FORMAT: u8 = 0x01;
pub const MANIFEST_LEN: usize = 1 + 8 + 32 + 32 + 32 + MLDSA_SIG; // 3414
pub const HISTORY_ACTIVE_MAX: u64 = 268_435_456; // 256 MiB — active-log compaction trigger

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompactionManifest {
    pub compacted_up_to_seq: u64,
    pub cold_blob_id: [u8; 32],
    pub cold_blob_key: [u8; 32],
    pub cold_root: [u8; 32],
    pub sig: Vec<u8>,
}

/// Bytes signed by account_key (116 B).
pub fn sig_message(
    compacted_up_to_seq: u64,
    cold_blob_id: &[u8; 32],
    cold_blob_key: &[u8; 32],
    cold_root: &[u8; 32],
) -> Vec<u8> {
    let mut m = Vec::with_capacity(10 + 1 + 1 + 8 + 32 + 32 + 32);
    m.extend_from_slice(MSG_COMPACT);
    m.push(0x00);
    m.push(COMPACT_FORMAT);
    m.extend_from_slice(&compacted_up_to_seq.to_le_bytes());
    m.extend_from_slice(cold_blob_id);
    m.extend_from_slice(cold_blob_key);
    m.extend_from_slice(cold_root);
    m
}

/// cold_root = Merkle root of exactly the cold block hashes [0..compacted_up_to_seq) in canonical order.
pub fn cold_root(cold_block_hashes: &[[u8; 32]]) -> Option<[u8; 32]> {
    archive_root(cold_block_hashes)
}

pub fn build_signed_manifest(
    account_seed: &[u8; 32],
    compacted_up_to_seq: u64,
    cold_blob_id: &[u8; 32],
    cold_blob_key: &[u8; 32],
    cold_root: &[u8; 32],
) -> Option<CompactionManifest> {
    let msg = sig_message(compacted_up_to_seq, cold_blob_id, cold_blob_key, cold_root);
    let sig = dsa_sign(account_seed, &msg)?;
    if sig.len() != MLDSA_SIG {
        return None;
    }
    Some(CompactionManifest {
        compacted_up_to_seq,
        cold_blob_id: *cold_blob_id,
        cold_blob_key: *cold_blob_key,
        cold_root: *cold_root,
        sig,
    })
}

pub fn encode_manifest(m: &CompactionManifest) -> Option<Vec<u8>> {
    if m.sig.len() != MLDSA_SIG {
        return None;
    }
    let mut o = Vec::with_capacity(MANIFEST_LEN);
    o.push(COMPACT_FORMAT);
    o.extend_from_slice(&m.compacted_up_to_seq.to_le_bytes());
    o.extend_from_slice(&m.cold_blob_id);
    o.extend_from_slice(&m.cold_blob_key);
    o.extend_from_slice(&m.cold_root);
    o.extend_from_slice(&m.sig);
    Some(o)
}

/// Invalid-safe parse (Gate 13): any violation → None.
pub fn parse_manifest(buf: &[u8]) -> Option<CompactionManifest> {
    if buf.len() != MANIFEST_LEN || buf[0] != COMPACT_FORMAT {
        return None;
    }
    let compacted_up_to_seq = u64::from_le_bytes(buf[1..9].try_into().ok()?);
    let mut cold_blob_id = [0u8; 32];
    cold_blob_id.copy_from_slice(&buf[9..41]);
    let mut cold_blob_key = [0u8; 32];
    cold_blob_key.copy_from_slice(&buf[41..73]);
    let mut cold_root = [0u8; 32];
    cold_root.copy_from_slice(&buf[73..105]);
    let sig = buf[105..MANIFEST_LEN].to_vec();
    Some(CompactionManifest {
        compacted_up_to_seq,
        cold_blob_id,
        cold_blob_key,
        cold_root,
        sig,
    })
}

/// Verify signature and structural invariants. `prev_seq` is the previous manifest's compacted_up_to_seq
/// (0 if none); `head` is the current head block_seq. Enforces monotonicity (no rollback) and a non-empty
/// active log after compaction (compacted_up_to_seq < head).
pub fn verify_manifest(
    m: &CompactionManifest,
    account_pub: &[u8],
    prev_seq: u64,
    head: u64,
) -> bool {
    if m.sig.len() != MLDSA_SIG {
        return false;
    }
    if m.compacted_up_to_seq <= prev_seq {
        return false; // monotonic, no rollback
    }
    if m.compacted_up_to_seq >= head {
        return false; // active log must stay non-empty
    }
    let msg = sig_message(
        m.compacted_up_to_seq,
        &m.cold_blob_id,
        &m.cold_blob_key,
        &m.cold_root,
    );
    dsa_verify(account_pub, &msg, &m.sig)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::dsa_pub_from_seed;
    use crate::handshake::account_id;
    use sha2::{Digest, Sha256};

    #[test]
    fn compact_manifest_kat() {
        // spec §348: compacted_up_to_seq=1000, cold_blob_id=aa×32, cold_blob_key=bb×32, cold_root=cc×32.
        let msg = sig_message(1000, &[0xaau8; 32], &[0xbbu8; 32], &[0xccu8; 32]);
        assert_eq!(msg.len(), 116);
        let h: [u8; 32] = Sha256::digest(&msg).into();
        assert_eq!(
            hex::encode(h),
            "5de07f2470a7bffc2dcb805a3db18a2ff39ed1459ccc1b806c4e347dd6725ca8"
        );
    }

    #[test]
    fn manifest_roundtrip_and_verify() {
        let seed = [0x77u8; 32];
        let pubk = dsa_pub_from_seed(&seed).unwrap();
        let _ = account_id(&pubk);
        let cr = cold_root(&[[0xa0u8; 32], [0xb0u8; 32]]).unwrap();
        let m = build_signed_manifest(&seed, 1000, &[0xaau8; 32], &[0xbbu8; 32], &cr).unwrap();
        let wire = encode_manifest(&m).unwrap();
        assert_eq!(wire.len(), MANIFEST_LEN);
        assert_eq!(wire.len(), 3414);
        let parsed = parse_manifest(&wire).unwrap();
        assert_eq!(parsed, m);
        // prev_seq=0, head=2000 → compacted 1000 valid (monotonic + active non-empty)
        assert!(verify_manifest(&parsed, &pubk, 0, 2000));
    }

    #[test]
    fn monotonic_and_nonempty_active() {
        let seed = [0x77u8; 32];
        let pubk = dsa_pub_from_seed(&seed).unwrap();
        let cr = cold_root(&[[0xa0u8; 32]]).unwrap();
        let m = build_signed_manifest(&seed, 1000, &[0xaau8; 32], &[0xbbu8; 32], &cr).unwrap();
        // rollback: compacted_up_to_seq <= prev_seq → reject
        assert!(!verify_manifest(&m, &pubk, 1000, 2000));
        assert!(!verify_manifest(&m, &pubk, 1500, 2000));
        // would empty the active log: compacted_up_to_seq >= head → reject
        assert!(!verify_manifest(&m, &pubk, 0, 1000));
        assert!(!verify_manifest(&m, &pubk, 0, 500));
        // valid window
        assert!(verify_manifest(&m, &pubk, 500, 1500));
    }

    #[test]
    fn tampered_or_wrong_key_rejected() {
        let seed = [0x77u8; 32];
        let pubk = dsa_pub_from_seed(&seed).unwrap();
        let cr = cold_root(&[[0xa0u8; 32]]).unwrap();
        let m = build_signed_manifest(&seed, 1000, &[0xaau8; 32], &[0xbbu8; 32], &cr).unwrap();
        let other = dsa_pub_from_seed(&[0x88u8; 32]).unwrap();
        assert!(!verify_manifest(&m, &other, 0, 2000));
        let mut bad = m.clone();
        bad.cold_root = [0x00u8; 32]; // signed field changed → signature invalid
        assert!(!verify_manifest(&bad, &pubk, 0, 2000));
    }

    #[test]
    fn bad_len_rejected() {
        assert!(parse_manifest(&[0u8; 100]).is_none());
    }
}
