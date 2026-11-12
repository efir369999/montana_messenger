//! Stage 6 (second front) — peer-recovery (Tier 2). When none of one's own devices survive, a shared
//! thread is pulled from a counterparty's device: authorization is by the requester's account_key
//! signature (the peer proves the requester is the thread's second party — not by knowing thread_id),
//! and the peer reseals ONLY that shared thread onto the requester's fresh ML-KEM-768 public key.
//!
//! RecoveryRequest (4582 B):
//!   format 1 (=0x01) ‖ requester_id 32 ‖ peer_id 32 ‖ fresh_kem_pub 1184 ‖ nonce 16 ‖ req_time u64 LE
//!   ‖ req_sig 3309   (ML-DSA-65 account_key over "mt-recover-req" ‖ 0x00 ‖ format ‖ requester_id
//!                     ‖ peer_id ‖ fresh_kem_pub ‖ nonce ‖ req_time — 1288 B).
//! RecoveryResponse: format 1 (=0x01) ‖ block_count u32 LE ‖ [ sealed_len u32 LE ‖ kem_sealed_block ]×count.
//!   Each block is ML-KEM-768 sealed to fresh_kem_pub: ct_seal 1088 ‖ ChaCha20-Poly1305(k, n, open block),
//!   (k, n) = HKDF-SHA-256(0×32, ss, "mt-recover-req", 44) — ss unique per encapsulation.

use crate::archive::{decode_block, encode_block, HistoryBlock};
use crate::crypto::{
    dsa_sign, dsa_verify, kem_decapsulate, kem_encapsulate, MLDSA_SIG, MLKEM_CT, MLKEM_PUB,
};
use crate::handshake::account_id;
use crate::kdf::hkdf_sha256;
use crate::ratchet::{open, seal};
use mt_codec::domain::MSG_RECOVER_REQ;

pub const RECOVER_FORMAT: u8 = 0x01;
pub const RECOVERY_REQUEST_LEN: usize = 1 + 32 + 32 + MLKEM_PUB + 16 + 8 + MLDSA_SIG; // 4582
pub const RECOVERY_MAX_AGE: u64 = 3600;

#[derive(Clone)]
pub struct RecoveryRequest {
    pub requester_id: [u8; 32],
    pub peer_id: [u8; 32],
    pub fresh_kem_pub: [u8; MLKEM_PUB],
    pub nonce: [u8; 16],
    pub req_time: u64,
    pub req_sig: Vec<u8>,
}

/// Bytes signed by the requester's account_key (1288 B).
pub fn sig_message(
    requester_id: &[u8; 32],
    peer_id: &[u8; 32],
    fresh_kem_pub: &[u8; MLKEM_PUB],
    nonce: &[u8; 16],
    req_time: u64,
) -> Vec<u8> {
    let mut m = Vec::with_capacity(14 + 1 + 1 + 32 + 32 + MLKEM_PUB + 16 + 8);
    m.extend_from_slice(MSG_RECOVER_REQ);
    m.push(0x00);
    m.push(RECOVER_FORMAT);
    m.extend_from_slice(requester_id);
    m.extend_from_slice(peer_id);
    m.extend_from_slice(fresh_kem_pub);
    m.extend_from_slice(nonce);
    m.extend_from_slice(&req_time.to_le_bytes());
    m
}

pub fn build_signed_request(
    account_seed: &[u8; 32],
    requester_id: &[u8; 32],
    peer_id: &[u8; 32],
    fresh_kem_pub: &[u8; MLKEM_PUB],
    nonce: &[u8; 16],
    req_time: u64,
) -> Option<RecoveryRequest> {
    let msg = sig_message(requester_id, peer_id, fresh_kem_pub, nonce, req_time);
    let sig = dsa_sign(account_seed, &msg)?;
    if sig.len() != MLDSA_SIG {
        return None;
    }
    Some(RecoveryRequest {
        requester_id: *requester_id,
        peer_id: *peer_id,
        fresh_kem_pub: *fresh_kem_pub,
        nonce: *nonce,
        req_time,
        req_sig: sig,
    })
}

pub fn encode_request(r: &RecoveryRequest) -> Option<Vec<u8>> {
    if r.req_sig.len() != MLDSA_SIG {
        return None;
    }
    let mut o = Vec::with_capacity(RECOVERY_REQUEST_LEN);
    o.push(RECOVER_FORMAT);
    o.extend_from_slice(&r.requester_id);
    o.extend_from_slice(&r.peer_id);
    o.extend_from_slice(&r.fresh_kem_pub);
    o.extend_from_slice(&r.nonce);
    o.extend_from_slice(&r.req_time.to_le_bytes());
    o.extend_from_slice(&r.req_sig);
    Some(o)
}

/// Invalid-safe parse (Gate 13): any violation → None.
pub fn parse_request(buf: &[u8]) -> Option<RecoveryRequest> {
    if buf.len() != RECOVERY_REQUEST_LEN || buf[0] != RECOVER_FORMAT {
        return None;
    }
    let mut requester_id = [0u8; 32];
    requester_id.copy_from_slice(&buf[1..33]);
    let mut peer_id = [0u8; 32];
    peer_id.copy_from_slice(&buf[33..65]);
    let mut fresh_kem_pub = [0u8; MLKEM_PUB];
    fresh_kem_pub.copy_from_slice(&buf[65..65 + MLKEM_PUB]);
    let mut off = 65 + MLKEM_PUB;
    let mut nonce = [0u8; 16];
    nonce.copy_from_slice(&buf[off..off + 16]);
    off += 16;
    let req_time = u64::from_le_bytes(buf[off..off + 8].try_into().ok()?);
    off += 8;
    let req_sig = buf[off..RECOVERY_REQUEST_LEN].to_vec();
    Some(RecoveryRequest {
        requester_id,
        peer_id,
        fresh_kem_pub,
        nonce,
        req_time,
        req_sig,
    })
}

/// Peer-side authorization: the requester's account_key signature is valid, requester_id binds to that
/// key (the requester proves being the thread's second party by signature — not by thread_id knowledge),
/// fresh_kem_pub is well-formed, and the request is fresh. Thread membership (requester_id is a recorded
/// counterparty) is the caller's check against its own thread table.
pub fn verify_request(r: &RecoveryRequest, requester_account_pub: &[u8], now: u64) -> bool {
    if r.req_sig.len() != MLDSA_SIG {
        return false;
    }
    if r.requester_id != account_id(requester_account_pub) {
        return false;
    }
    if now < r.req_time || now - r.req_time > RECOVERY_MAX_AGE {
        return false;
    }
    let msg = sig_message(
        &r.requester_id,
        &r.peer_id,
        &r.fresh_kem_pub,
        &r.nonce,
        r.req_time,
    );
    dsa_verify(requester_account_pub, &msg, &r.req_sig)
}

fn seal_key_nonce(ss: &[u8; 32]) -> ([u8; 32], [u8; 12]) {
    let okm = hkdf_sha256(&[0u8; 32], ss, MSG_RECOVER_REQ, 44);
    let mut k = [0u8; 32];
    k.copy_from_slice(&okm[..32]);
    let mut n = [0u8; 12];
    n.copy_from_slice(&okm[32..44]);
    (k, n)
}

fn recover_ad() -> Vec<u8> {
    let mut ad = MSG_RECOVER_REQ.to_vec();
    ad.push(0x00);
    ad
}

/// Reseal one open HistoryBlock onto fresh_kem_pub: ct_seal(1088) ‖ ChaCha20-Poly1305(k, n, open block).
pub fn kem_seal_block(fresh_kem_pub: &[u8; MLKEM_PUB], b: &HistoryBlock) -> Option<Vec<u8>> {
    let (ct_seal, ss) = kem_encapsulate(fresh_kem_pub)?;
    let (k, n) = seal_key_nonce(&ss);
    let ct = seal(&k, &n, &encode_block(b), &recover_ad());
    let mut out = Vec::with_capacity(MLKEM_CT + ct.len());
    out.extend_from_slice(&ct_seal);
    out.extend_from_slice(&ct);
    Some(out)
}

/// Open a resealed block with the requester's fresh KEM secret key.
pub fn kem_open_block(fresh_kem_sk: &[u8], sealed: &[u8]) -> Option<HistoryBlock> {
    if sealed.len() < MLKEM_CT {
        return None;
    }
    let ss = kem_decapsulate(fresh_kem_sk, &sealed[..MLKEM_CT])?;
    let (k, n) = seal_key_nonce(&ss);
    let pt = open(&k, &n, &sealed[MLKEM_CT..], &recover_ad())?;
    decode_block(&pt)
}

/// RecoveryResponse: only the shared thread's blocks, each KEM-sealed to fresh_kem_pub.
pub fn encode_response(
    fresh_kem_pub: &[u8; MLKEM_PUB],
    thread_blocks: &[HistoryBlock],
) -> Option<Vec<u8>> {
    let mut o = Vec::new();
    o.push(RECOVER_FORMAT);
    o.extend_from_slice(&(thread_blocks.len() as u32).to_le_bytes());
    for b in thread_blocks {
        let sealed = kem_seal_block(fresh_kem_pub, b)?;
        o.extend_from_slice(&(sealed.len() as u32).to_le_bytes());
        o.extend_from_slice(&sealed);
    }
    Some(o)
}

/// Parse + open a RecoveryResponse with the fresh KEM secret key. None on any framing/decrypt violation.
pub fn parse_and_open_response(fresh_kem_sk: &[u8], buf: &[u8]) -> Option<Vec<HistoryBlock>> {
    if buf.len() < 5 || buf[0] != RECOVER_FORMAT {
        return None;
    }
    let count = u32::from_le_bytes(buf[1..5].try_into().ok()?) as usize;
    let mut off = 5usize;
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
        blocks.push(kem_open_block(fresh_kem_sk, &buf[off..off + len])?);
        off += len;
    }
    if off != buf.len() {
        return None;
    }
    Some(blocks)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::archive::{HistoryItem, DIR_IN, DIR_OUT};
    use crate::crypto::{dsa_pub_from_seed, kem_keypair_from_seed};
    use sha2::{Digest, Sha256};

    fn thread_block(seq: u64, text: &[u8]) -> HistoryBlock {
        HistoryBlock {
            block_seq: seq,
            items: vec![HistoryItem {
                conv_id: [0x22u8; 32],
                dir: if seq % 2 == 0 { DIR_OUT } else { DIR_IN },
                send_time: 1000 + seq,
                content: text.to_vec(),
            }],
        }
    }

    #[test]
    fn recover_req_kat() {
        // spec §247: requester_id=33×32, peer_id=44×32, fresh_kem_pub=55×1184, nonce=66×16, req_time=1000.
        let msg = sig_message(
            &[0x33u8; 32],
            &[0x44u8; 32],
            &[0x55u8; MLKEM_PUB],
            &[0x66u8; 16],
            1000,
        );
        assert_eq!(msg.len(), 1288);
        let h: [u8; 32] = Sha256::digest(&msg).into();
        assert_eq!(
            hex::encode(h),
            "0f64e5b6309d09c8f826149212ec0a711369b1beb9975d26e8ddddc29149691d"
        );
    }

    #[test]
    fn request_roundtrip_and_verify() {
        let seed = [0x77u8; 32];
        let pubk = dsa_pub_from_seed(&seed).unwrap();
        let rid = account_id(&pubk);
        let (kem_pub, _kem_sk) = kem_keypair_from_seed(&[0x01u8; 64]).unwrap();
        let req = build_signed_request(&seed, &rid, &[0x44u8; 32], &kem_pub, &[0x66u8; 16], 1000)
            .unwrap();
        let wire = encode_request(&req).unwrap();
        assert_eq!(wire.len(), RECOVERY_REQUEST_LEN);
        assert_eq!(wire.len(), 4582);
        let parsed = parse_request(&wire).unwrap();
        assert!(verify_request(&parsed, &pubk, 1000));
    }

    #[test]
    fn authorization_and_freshness() {
        let seed = [0x77u8; 32];
        let pubk = dsa_pub_from_seed(&seed).unwrap();
        let rid = account_id(&pubk);
        let (kem_pub, _) = kem_keypair_from_seed(&[0x01u8; 64]).unwrap();
        let req = build_signed_request(&seed, &rid, &[0x44u8; 32], &kem_pub, &[0x66u8; 16], 1000)
            .unwrap();
        // wrong requester key → not authorized (peer cannot be tricked without the requester's key)
        let other = dsa_pub_from_seed(&[0x88u8; 32]).unwrap();
        assert!(!verify_request(&req, &other, 1000));
        // stale / future
        assert!(!verify_request(&req, &pubk, 1000 + RECOVERY_MAX_AGE + 1));
        assert!(!verify_request(&req, &pubk, 999));
    }

    #[test]
    fn response_reseal_roundtrip() {
        let (kem_pub, kem_sk) = kem_keypair_from_seed(&[0x02u8; 64]).unwrap();
        let blocks = vec![
            thread_block(0, b"hi"),
            thread_block(1, b"there"),
            thread_block(2, b"again"),
        ];
        let wire = encode_response(&kem_pub, &blocks).unwrap();
        let opened = parse_and_open_response(&kem_sk, &wire).unwrap();
        assert_eq!(opened, blocks);
        // wrong KEM secret key → cannot open
        let (_p2, sk2) = kem_keypair_from_seed(&[0x03u8; 64]).unwrap();
        assert!(parse_and_open_response(&sk2, &wire).is_none());
    }

    #[test]
    fn bad_request_len_rejected() {
        assert!(parse_request(&[0u8; 100]).is_none());
    }

    #[test]
    fn truncated_response_rejected() {
        let (kem_pub, kem_sk) = kem_keypair_from_seed(&[0x02u8; 64]).unwrap();
        let wire = encode_response(&kem_pub, &[thread_block(0, b"x")]).unwrap();
        assert!(parse_and_open_response(&kem_sk, &wire[..wire.len() - 1]).is_none());
    }
}
