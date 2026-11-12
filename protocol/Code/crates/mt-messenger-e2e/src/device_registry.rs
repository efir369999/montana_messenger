//! Stage 10 — signed device registry (multi-device, canonical profile).
//! DeviceRegistry: format 0x02 ‖ registry_seq u64 LE ‖ registry_time u64 LE ‖ entry_count u16 LE
//! ‖ entries ‖ registry_sig (ML-DSA-65 over "mt-device-registry"‖0x00‖<everything up to sig>).
//! Parsing is invalid-safe (Gate 13): any violation → Reject, NEVER panic.

use crate::crypto::{dsa_verify, MLDSA_SIG};

pub const REGISTRY_FORMAT: u8 = 0x02;
pub const DEVICE_ID_LEN: usize = 16;
pub const DEVICE_KEM_PUB: usize = 1184;
pub const ENTRY_LEN: usize = DEVICE_ID_LEN + DEVICE_KEM_PUB + 8 + 1; // 1209
pub const REGISTRY_DOMAIN: &[u8] = b"mt-device-registry";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceEntry {
    pub device_id: [u8; DEVICE_ID_LEN],
    pub device_kem_pub: [u8; DEVICE_KEM_PUB],
    pub added_at: u64,
    pub revoked: bool,
}

pub fn encode_entry(e: &DeviceEntry) -> Vec<u8> {
    let mut o = Vec::with_capacity(ENTRY_LEN);
    o.extend_from_slice(&e.device_id);
    o.extend_from_slice(&e.device_kem_pub);
    o.extend_from_slice(&e.added_at.to_le_bytes());
    o.push(if e.revoked { 0x01 } else { 0x00 });
    o
}

/// Bytes signed by account_key: domain ‖ 0x00 ‖ format ‖ seq ‖ time ‖ count ‖ entries.
pub fn registry_sign_message(
    registry_seq: u64,
    registry_time: u64,
    entries: &[DeviceEntry],
) -> Vec<u8> {
    let mut m = REGISTRY_DOMAIN.to_vec();
    m.push(0x00);
    m.push(REGISTRY_FORMAT);
    m.extend_from_slice(&registry_seq.to_le_bytes());
    m.extend_from_slice(&registry_time.to_le_bytes());
    m.extend_from_slice(&(entries.len() as u16).to_le_bytes());
    for e in entries {
        m.extend_from_slice(&encode_entry(e));
    }
    m
}

/// Full serialized registry (for publication): format‖seq‖time‖count‖entries‖sig.
pub fn encode_registry(
    registry_seq: u64,
    registry_time: u64,
    entries: &[DeviceEntry],
    registry_sig: &[u8; MLDSA_SIG],
) -> Vec<u8> {
    let mut o = Vec::new();
    o.push(REGISTRY_FORMAT);
    o.extend_from_slice(&registry_seq.to_le_bytes());
    o.extend_from_slice(&registry_time.to_le_bytes());
    o.extend_from_slice(&(entries.len() as u16).to_le_bytes());
    for e in entries {
        o.extend_from_slice(&encode_entry(e));
    }
    o.extend_from_slice(registry_sig);
    o
}

#[derive(Debug, PartialEq, Eq)]
pub struct ParsedRegistry {
    pub registry_seq: u64,
    pub registry_time: u64,
    pub entries: Vec<DeviceEntry>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum RegistryOutcome {
    Ok(ParsedRegistry),
    Reject,
}

/// Invalid-safe parsing + account_key signature verification. Reject on any violation.
pub fn parse_and_verify(buf: &[u8], account_pub: &[u8]) -> RegistryOutcome {
    if buf.len() < 19 {
        return RegistryOutcome::Reject;
    }
    if buf[0] != REGISTRY_FORMAT {
        return RegistryOutcome::Reject;
    }
    let registry_seq = u64::from_le_bytes(buf[1..9].try_into().unwrap());
    let registry_time = u64::from_le_bytes(buf[9..17].try_into().unwrap());
    let count = u16::from_le_bytes(buf[17..19].try_into().unwrap()) as usize;
    let entries_len = match count.checked_mul(ENTRY_LEN) {
        Some(v) => v,
        None => return RegistryOutcome::Reject,
    };
    if buf.len() != 19 + entries_len + MLDSA_SIG {
        return RegistryOutcome::Reject;
    }
    let mut entries = Vec::with_capacity(count);
    let mut p = 19;
    for _ in 0..count {
        let mut device_id = [0u8; DEVICE_ID_LEN];
        device_id.copy_from_slice(&buf[p..p + DEVICE_ID_LEN]);
        p += DEVICE_ID_LEN;
        let mut device_kem_pub = [0u8; DEVICE_KEM_PUB];
        device_kem_pub.copy_from_slice(&buf[p..p + DEVICE_KEM_PUB]);
        p += DEVICE_KEM_PUB;
        let added_at = u64::from_le_bytes(buf[p..p + 8].try_into().unwrap());
        p += 8;
        let revoked = match buf[p] {
            0x00 => false,
            0x01 => true,
            _ => return RegistryOutcome::Reject,
        };
        p += 1;
        entries.push(DeviceEntry {
            device_id,
            device_kem_pub,
            added_at,
            revoked,
        });
    }
    let sig = &buf[p..p + MLDSA_SIG];
    let msg = registry_sign_message(registry_seq, registry_time, &entries);
    if !dsa_verify(account_pub, &msg, sig) {
        return RegistryOutcome::Reject;
    }
    RegistryOutcome::Ok(ParsedRegistry {
        registry_seq,
        registry_time,
        entries,
    })
}

/// Active (revoked == false) devices for fan-out.
pub fn active_devices(reg: &ParsedRegistry) -> Vec<&DeviceEntry> {
    reg.entries.iter().filter(|e| !e.revoked).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    #[test]
    fn device_registry_spec_kat() {
        let entry = DeviceEntry {
            device_id: [0x11; 16],
            device_kem_pub: [0x77; 1184],
            added_at: 1000,
            revoked: false,
        };
        assert_eq!(encode_entry(&entry).len(), ENTRY_LEN);
        let msg = registry_sign_message(5, 2000, &[entry]);
        assert_eq!(msg.len(), 1247);
        assert_eq!(
            hex::encode(Sha256::digest(&msg)),
            "d32761561a28a29b68125de252c05c9f529185fd7d5182863b4bbc0720a3e863"
        );
    }

    #[test]
    fn parse_rejects_malformed() {
        assert_eq!(
            parse_and_verify(&[0u8; 10], &[0u8; 1952]),
            RegistryOutcome::Reject
        );
        let mut bad = vec![0x01u8];
        bad.extend_from_slice(&[0u8; 18 + MLDSA_SIG]);
        assert_eq!(
            parse_and_verify(&bad, &[0u8; 1952]),
            RegistryOutcome::Reject
        );
        let entry = DeviceEntry {
            device_id: [0x11; 16],
            device_kem_pub: [0x77; 1184],
            added_at: 1000,
            revoked: false,
        };
        let reg = encode_registry(5, 2000, &[entry], &[0u8; MLDSA_SIG]);
        assert_eq!(
            parse_and_verify(&reg, &[0u8; 1952]),
            RegistryOutcome::Reject
        );
    }
}
