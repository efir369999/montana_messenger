//! Stage 3 (second front) — device onboarding + full catch-up. ArchiveSyncRequest is the single
//! mechanism to pull one's own archive (Stages 3–5): a device asks any live device of the same seed
//! for the block range block_seq ≥ from_block_seq across all writers, in canonical (writer_tag, block_seq)
//! order; the requester dedups by (writer_tag, block_seq). from_block_seq = 0 → full archive (onboarding).
//!
//! ArchiveSyncRequest (3374 B):
//!   format 1 (=0x01) ‖ requester_id 32 ‖ from_block_seq u64 LE ‖ nonce 16 ‖ req_time u64 LE ‖ sig 3309
//!   sig = ML-DSA-65 account_key over "mt-archive-sync" ‖ 0x00 ‖ format ‖ requester_id ‖ from_block_seq
//!         ‖ nonce ‖ req_time (81 B).
//! ArchiveSyncResponse: format 1 (=0x01) ‖ head_block_seq u64 LE ‖ block_count u32 LE
//!   ‖ [ sealed_len u32 LE ‖ sealed_block ]×block_count  (as-stored: shared history_key across own devices).

use crate::crypto::{dsa_sign, dsa_verify, MLDSA_SIG};
use crate::handshake::account_id;
use mt_codec::domain::MSG_ARCHIVE_SYNC;

pub const SYNC_FORMAT: u8 = 0x01;
pub const REQUEST_LEN: usize = 1 + 32 + 8 + 16 + 8 + MLDSA_SIG; // 3374
pub const ARCHIVE_SYNC_MAX_AGE: u64 = 3600;

#[derive(Clone)]
pub struct ArchiveSyncRequest {
    pub requester_id: [u8; 32],
    pub from_block_seq: u64,
    pub nonce: [u8; 16],
    pub req_time: u64,
    pub sig: Vec<u8>, // ML-DSA-65, MLDSA_SIG bytes
}

/// Bytes signed by account_key (81 B): domain ‖ 0x00 ‖ format ‖ requester_id ‖ from_block_seq ‖ nonce ‖ req_time.
pub fn sig_message(
    requester_id: &[u8; 32],
    from_block_seq: u64,
    nonce: &[u8; 16],
    req_time: u64,
) -> Vec<u8> {
    let mut m = Vec::with_capacity(15 + 1 + 1 + 32 + 8 + 16 + 8);
    m.extend_from_slice(MSG_ARCHIVE_SYNC);
    m.push(0x00);
    m.push(SYNC_FORMAT);
    m.extend_from_slice(requester_id);
    m.extend_from_slice(&from_block_seq.to_le_bytes());
    m.extend_from_slice(nonce);
    m.extend_from_slice(&req_time.to_le_bytes());
    m
}

/// Build a request signed by the account_key (seed of the requesting device — same seed, DeviceRegistry).
pub fn build_signed_request(
    account_seed: &[u8; 32],
    requester_id: &[u8; 32],
    from_block_seq: u64,
    nonce: &[u8; 16],
    req_time: u64,
) -> Option<ArchiveSyncRequest> {
    let msg = sig_message(requester_id, from_block_seq, nonce, req_time);
    let sig = dsa_sign(account_seed, &msg)?;
    if sig.len() != MLDSA_SIG {
        return None;
    }
    Some(ArchiveSyncRequest {
        requester_id: *requester_id,
        from_block_seq,
        nonce: *nonce,
        req_time,
        sig,
    })
}

pub fn encode_request(r: &ArchiveSyncRequest) -> Option<Vec<u8>> {
    if r.sig.len() != MLDSA_SIG {
        return None;
    }
    let mut o = Vec::with_capacity(REQUEST_LEN);
    o.push(SYNC_FORMAT);
    o.extend_from_slice(&r.requester_id);
    o.extend_from_slice(&r.from_block_seq.to_le_bytes());
    o.extend_from_slice(&r.nonce);
    o.extend_from_slice(&r.req_time.to_le_bytes());
    o.extend_from_slice(&r.sig);
    Some(o)
}

/// Invalid-safe parse (Gate 13): any violation → None, never panic.
pub fn parse_request(buf: &[u8]) -> Option<ArchiveSyncRequest> {
    if buf.len() != REQUEST_LEN {
        return None;
    }
    if buf[0] != SYNC_FORMAT {
        return None;
    }
    let mut requester_id = [0u8; 32];
    requester_id.copy_from_slice(&buf[1..33]);
    let from_block_seq = u64::from_le_bytes(buf[33..41].try_into().ok()?);
    let mut nonce = [0u8; 16];
    nonce.copy_from_slice(&buf[41..57]);
    let req_time = u64::from_le_bytes(buf[57..65].try_into().ok()?);
    let sig = buf[65..REQUEST_LEN].to_vec();
    Some(ArchiveSyncRequest {
        requester_id,
        from_block_seq,
        nonce,
        req_time,
        sig,
    })
}

/// Authorize a request: requester_id binds to account_pub, ML-DSA-65 signature valid, and fresh
/// (now − req_time ≤ ARCHIVE_SYNC_MAX_AGE, and not from the future). Nonce one-time-use is the caller's
/// cache (out of codec scope). The archive is always one's own (single seed) — a foreign key cannot ask.
pub fn verify_request(r: &ArchiveSyncRequest, account_pub: &[u8], now: u64) -> bool {
    if r.sig.len() != MLDSA_SIG {
        return false;
    }
    if r.requester_id != account_id(account_pub) {
        return false;
    }
    if now < r.req_time || now - r.req_time > ARCHIVE_SYNC_MAX_AGE {
        return false;
    }
    let msg = sig_message(&r.requester_id, r.from_block_seq, &r.nonce, r.req_time);
    dsa_verify(account_pub, &msg, &r.sig)
}

/// Response carries as-stored sealed blocks (shared history_key across own devices).
pub fn encode_response(head_block_seq: u64, sealed_blocks: &[Vec<u8>]) -> Vec<u8> {
    let mut o = Vec::new();
    o.push(SYNC_FORMAT);
    o.extend_from_slice(&head_block_seq.to_le_bytes());
    o.extend_from_slice(&(sealed_blocks.len() as u32).to_le_bytes());
    for b in sealed_blocks {
        o.extend_from_slice(&(b.len() as u32).to_le_bytes());
        o.extend_from_slice(b);
    }
    o
}

/// Invalid-safe parse of a response → (head_block_seq, sealed blocks). None on any framing violation.
pub fn parse_response(buf: &[u8]) -> Option<(u64, Vec<Vec<u8>>)> {
    if buf.len() < 13 || buf[0] != SYNC_FORMAT {
        return None;
    }
    let head_block_seq = u64::from_le_bytes(buf[1..9].try_into().ok()?);
    let count = u32::from_le_bytes(buf[9..13].try_into().ok()?) as usize;
    let mut off = 13usize;
    let mut blocks = Vec::with_capacity(count);
    for _ in 0..count {
        if off + 4 > buf.len() {
            return None;
        }
        let len = u32::from_le_bytes(buf[off..off + 4].try_into().ok()?) as usize;
        off += 4;
        if off + len > buf.len() {
            return None;
        }
        blocks.push(buf[off..off + len].to_vec());
        off += len;
    }
    if off != buf.len() {
        return None;
    }
    Some((head_block_seq, blocks))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::dsa_pub_from_seed;
    use sha2::{Digest, Sha256};

    #[test]
    fn archive_sync_kat() {
        // spec §161: format=0x01, requester_id=33×32, from_block_seq=0, nonce=66×16, req_time=1000 → 81 B.
        let msg = sig_message(&[0x33u8; 32], 0, &[0x66u8; 16], 1000);
        assert_eq!(msg.len(), 81);
        let h: [u8; 32] = Sha256::digest(&msg).into();
        assert_eq!(
            hex::encode(h),
            "9ad64732aada7be070350ffd4c96412e0343c28f604bb153553849abdaad63f5"
        );
    }

    #[test]
    fn request_roundtrip_and_verify() {
        let seed = [0x77u8; 32];
        let pubk = dsa_pub_from_seed(&seed).unwrap();
        let rid = account_id(&pubk);
        let req = build_signed_request(&seed, &rid, 0, &[0x01u8; 16], 1000).unwrap();
        let enc = encode_request(&req).unwrap();
        assert_eq!(enc.len(), REQUEST_LEN);
        assert_eq!(enc.len(), 3374);
        let parsed = parse_request(&enc).unwrap();
        assert_eq!(parsed.requester_id, rid);
        assert_eq!(parsed.from_block_seq, 0);
        assert!(verify_request(&parsed, &pubk, 1000));
        assert!(verify_request(&parsed, &pubk, 1000 + ARCHIVE_SYNC_MAX_AGE));
    }

    #[test]
    fn stale_request_rejected() {
        let seed = [0x77u8; 32];
        let pubk = dsa_pub_from_seed(&seed).unwrap();
        let rid = account_id(&pubk);
        let req = build_signed_request(&seed, &rid, 0, &[0x01u8; 16], 1000).unwrap();
        assert!(!verify_request(
            &req,
            &pubk,
            1000 + ARCHIVE_SYNC_MAX_AGE + 1
        )); // too old
        assert!(!verify_request(&req, &pubk, 999)); // from the future
    }

    #[test]
    fn wrong_key_or_id_rejected() {
        let seed = [0x77u8; 32];
        let pubk = dsa_pub_from_seed(&seed).unwrap();
        let rid = account_id(&pubk);
        let req = build_signed_request(&seed, &rid, 0, &[0x01u8; 16], 1000).unwrap();
        // different key does not authorize
        let other = dsa_pub_from_seed(&[0x88u8; 32]).unwrap();
        assert!(!verify_request(&req, &other, 1000));
        // tampered requester_id breaks the id binding and the signature
        let mut bad = req.clone();
        bad.requester_id = [0x00u8; 32];
        assert!(!verify_request(&bad, &pubk, 1000));
    }

    #[test]
    fn tampered_field_breaks_signature() {
        let seed = [0x77u8; 32];
        let pubk = dsa_pub_from_seed(&seed).unwrap();
        let rid = account_id(&pubk);
        let req = build_signed_request(&seed, &rid, 5, &[0x01u8; 16], 1000).unwrap();
        let mut bad = req.clone();
        bad.from_block_seq = 6; // signed field changed → signature invalid
        assert!(!verify_request(&bad, &pubk, 1000));
    }

    #[test]
    fn response_roundtrip() {
        let b0 = vec![1u8, 2, 3];
        let b1 = vec![9u8; 40];
        let enc = encode_response(7, &[b0.clone(), b1.clone()]);
        let (head, blocks) = parse_response(&enc).unwrap();
        assert_eq!(head, 7);
        assert_eq!(blocks, vec![b0, b1]);
    }

    #[test]
    fn response_truncated_rejected() {
        let enc = encode_response(7, &[vec![1u8, 2, 3]]);
        assert_eq!(parse_response(&enc[..enc.len() - 1]), None);
    }

    #[test]
    fn request_wrong_len_rejected() {
        assert!(parse_request(&[0u8; 10]).is_none());
        let mut enc = encode_request(
            &build_signed_request(&[0x77u8; 32], &[0x33u8; 32], 0, &[0x01u8; 16], 1000).unwrap(),
        )
        .unwrap();
        enc.push(0xff);
        assert!(parse_request(&enc).is_none());
    }
}
