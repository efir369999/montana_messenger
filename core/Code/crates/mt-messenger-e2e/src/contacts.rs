//! Stage 11 — contacts, @username, search (canonical codecs).
//! @username claim signature, contacts key from seed, ContactRecord/ContactList.
//! Parsing is invalid-safe (Gate 13): violation → None/Reject, NEVER panic.

use crate::kdf::hkdf_sha256;

pub const MAX_CONTACTS: usize = 4096;
pub const MAX_CONTACTS_BLOB: usize = 4 * 1024 * 1024;
pub const USERNAME_MAX: usize = 32;
pub const DISPLAY_MAX: usize = 64;

/// @username claim signature message: "mt-username"‖0x00‖username‖account_id.
pub fn username_claim_message(username: &[u8], account_id: &[u8; 32]) -> Vec<u8> {
    let mut m = b"mt-username".to_vec();
    m.push(0x00);
    m.extend_from_slice(username);
    m.extend_from_slice(account_id);
    m
}

/// @username release signature message (separate domain — the claim is not replayed):
/// "mt-username-release"‖0x00‖username‖account_id‖release_time_le8.
pub fn username_release_message(
    username: &[u8],
    account_id: &[u8; 32],
    release_time: u64,
) -> Vec<u8> {
    let mut m = b"mt-username-release".to_vec();
    m.push(0x00);
    m.extend_from_slice(username);
    m.extend_from_slice(account_id);
    m.extend_from_slice(&release_time.to_le_bytes());
    m
}

/// contacts_key = HKDF-SHA-256(salt=0×32, IKM=entropy_32, info="mt-contacts-key", 32).
pub fn contacts_key(entropy_32: &[u8; 32]) -> [u8; 32] {
    let okm = hkdf_sha256(&[0u8; 32], entropy_32, b"mt-contacts-key", 32);
    let mut out = [0u8; 32];
    out.copy_from_slice(&okm);
    out
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContactRecord {
    pub account_id: [u8; 32],
    pub verified: bool,
    pub username: Vec<u8>,
    pub display_name: Vec<u8>,
    pub added_at: u64,
}

fn is_username_ok(u: &[u8]) -> bool {
    u.len() <= USERNAME_MAX
        && u.iter()
            .all(|&b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_')
}

pub fn encode_contact_record(r: &ContactRecord) -> Vec<u8> {
    let mut o = Vec::with_capacity(32 + 1 + 1 + r.username.len() + 1 + r.display_name.len() + 8);
    o.extend_from_slice(&r.account_id);
    o.push(if r.verified { 0x01 } else { 0x00 });
    o.push(r.username.len() as u8);
    o.extend_from_slice(&r.username);
    o.push(r.display_name.len() as u8);
    o.extend_from_slice(&r.display_name);
    o.extend_from_slice(&r.added_at.to_le_bytes());
    o
}

/// Invalid-safe parsing of one record from position p; returns (record, next_p) or None.
pub fn decode_contact_record_at(b: &[u8], p: usize) -> Option<(ContactRecord, usize)> {
    let mut i = p;
    if b.len() < i + 34 {
        return None;
    }
    let mut account_id = [0u8; 32];
    account_id.copy_from_slice(&b[i..i + 32]);
    i += 32;
    let verified = match b[i] {
        0x00 => false,
        0x01 => true,
        _ => return None,
    };
    i += 1;
    let ulen = b[i] as usize;
    i += 1;
    if ulen > USERNAME_MAX || b.len() < i + ulen + 1 {
        return None;
    }
    let username = b[i..i + ulen].to_vec();
    if !is_username_ok(&username) {
        return None;
    }
    i += ulen;
    let dlen = b[i] as usize;
    i += 1;
    if dlen > DISPLAY_MAX || b.len() < i + dlen + 8 {
        return None;
    }
    let display_name = b[i..i + dlen].to_vec();
    if core::str::from_utf8(&display_name).is_err() {
        return None;
    }
    i += dlen;
    let added_at = u64::from_le_bytes(b[i..i + 8].try_into().unwrap());
    i += 8;
    Some((
        ContactRecord {
            account_id,
            verified,
            username,
            display_name,
            added_at,
        },
        i,
    ))
}

/// ContactList = list_version(0x01) ‖ count u16 LE ‖ [ContactRecord × count]. Invalid-safe.
pub fn decode_contact_list(b: &[u8]) -> Option<Vec<ContactRecord>> {
    if b.len() < 3 || b[0] != 0x01 {
        return None;
    }
    let count = u16::from_le_bytes(b[1..3].try_into().unwrap()) as usize;
    if count > MAX_CONTACTS {
        return None;
    }
    let mut out = Vec::with_capacity(count);
    let mut p = 3;
    for _ in 0..count {
        let (rec, np) = decode_contact_record_at(b, p)?;
        out.push(rec);
        p = np;
    }
    Some(out)
}

pub fn encode_contact_list(records: &[ContactRecord]) -> Vec<u8> {
    let mut o = vec![0x01u8];
    o.extend_from_slice(&(records.len() as u16).to_le_bytes());
    for r in records {
        o.extend_from_slice(&encode_contact_record(r));
    }
    o
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    fn zero_acc() -> [u8; 32] {
        hex::decode("9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21")
            .unwrap()
            .try_into()
            .unwrap()
    }

    #[test]
    fn username_claim_spec_kat() {
        let msg = username_claim_message(b"alice", &zero_acc());
        assert_eq!(msg.len(), 49);
        assert_eq!(
            hex::encode(Sha256::digest(&msg)),
            "3dd4fd698cb00f19ee52888af860e14d48bc50674c77e01e576cf024161021b6"
        );
    }

    #[test]
    fn contacts_key_spec_kat() {
        assert_eq!(
            hex::encode(contacts_key(&[0x55; 32])),
            "8a341c252f20b83f33ba2471fd915b11bed788c0b23f205cf8ce3a4de2c65301"
        );
    }

    #[test]
    fn contact_record_spec_kat() {
        let r = ContactRecord {
            account_id: zero_acc(),
            verified: true,
            username: b"alice".to_vec(),
            display_name: b"Alice".to_vec(),
            added_at: 1000,
        };
        let enc = encode_contact_record(&r);
        assert_eq!(enc.len(), 53);
        assert_eq!(
            hex::encode(&enc),
            "9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a210105616c69636505416c696365e803000000000000"
        );
        // round-trip through the list
        let list = encode_contact_list(std::slice::from_ref(&r));
        let back = decode_contact_list(&list).unwrap();
        assert_eq!(back, vec![r]);
    }

    #[test]
    fn decode_rejects_malformed() {
        // verified outside {0,1}
        let mut bad = zero_acc().to_vec();
        bad.push(0x02);
        bad.extend_from_slice(&[0, 0]);
        bad.extend_from_slice(&1000u64.to_le_bytes());
        assert!(decode_contact_record_at(&bad, 0).is_none());
        // username with an invalid character (space)
        let r = ContactRecord {
            account_id: zero_acc(),
            verified: false,
            username: b"al ce".to_vec(),
            display_name: vec![],
            added_at: 0,
        };
        assert!(decode_contact_record_at(&encode_contact_record(&r), 0).is_none());
        // list shorter than header
        assert!(decode_contact_list(&[0x01, 0x05]).is_none());
        // invalid list_version
        assert!(decode_contact_list(&[0x02, 0x00, 0x00]).is_none());
    }
}
