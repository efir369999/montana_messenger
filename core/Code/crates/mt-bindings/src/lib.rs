//! Montana-bindings — the single source of truth of Montana for non-Rust clients.
//!
//! Re-exports canonical functions from mt-mnemonic / mt-crypto / mt-state / mt-account
//! through a stable C ABI (for iOS xcframework + Android cdylib JNI) and WASM bindings
//! (for web). All clients must call THESE functions rather than reimplement
//! PBKDF2/HKDF/SHA/ML-DSA/address-derivation/transaction-encoding in native code.
//!
//! Spec invariant [SSOT-Rust] — see `Formal-Docs/02-Spec/SSOT-Rust.md`.

use core::panic::AssertUnwindSafe;

use sha2::{Digest as _, Sha256};

#[cfg(all(not(target_arch = "wasm32"), feature = "network"))]
pub mod mdns;
#[cfg(all(not(target_arch = "wasm32"), feature = "network"))]
pub mod muq_addressing;
#[cfg(all(not(target_arch = "wasm32"), feature = "network"))]
pub mod network;
#[cfg(all(not(target_arch = "wasm32"), feature = "network"))]
pub mod rendezvous;

#[cfg(not(target_arch = "wasm32"))]
pub mod ffi_c;

#[cfg(not(target_arch = "wasm32"))]
pub mod ffi_e2e;

/// C ABI of the names layer (Montana Names).
pub mod ffi_names;

#[cfg(not(target_arch = "wasm32"))]
pub mod ffi_noise;

#[cfg(not(target_arch = "wasm32"))]
pub mod wake;

#[cfg(target_arch = "wasm32")]
mod ffi_wasm;

#[cfg(target_os = "android")]
mod ffi_jni;

pub const ABI_VERSION: u32 = 1;

pub const MT_MASTER_SEED_LEN: usize = 64;
pub const MT_MLDSA_SEED_LEN: usize = 32;
pub const MT_MLDSA_PUBKEY_SIZE: usize = 1952;
pub const MT_MLDSA_SECKEY_SIZE: usize = 4032;
pub const MT_MLDSA_SIG_SIZE: usize = 3309;
pub const MT_ACCOUNT_ID_LEN: usize = 32;
pub const MT_HISTORY_KEY_LEN: usize = 32;
pub const MT_MAX_MNEMONIC_BYTES: usize = 512;
pub const MT_MIN_EXTRA_ENTROPY: usize = 16;

pub const MT_MLKEM_SEED_LEN: usize = 64;
pub const MT_MLKEM_PUBKEY_SIZE: usize = 1184;
pub const MT_MLKEM_SECKEY_SIZE: usize = 2400;
pub const MT_MLKEM_CT_SIZE: usize = 1088;
pub const MT_MLKEM_SS_SIZE: usize = 32;

// [C-1] SSOT cross-check: MT_* sizes match mt-crypto (native). The literals are needed
// on wasm too (where mt-crypto is unavailable), so they are duplicated, but drift is caught at build time.
#[cfg(not(target_arch = "wasm32"))]
const _: () = {
    assert!(MT_MLDSA_PUBKEY_SIZE == mt_crypto::PUBLIC_KEY_SIZE);
    assert!(MT_MLDSA_SECKEY_SIZE == mt_crypto::SECRET_KEY_SIZE);
    assert!(MT_MLDSA_SIG_SIZE == mt_crypto::SIGNATURE_SIZE);
    assert!(MT_MLKEM_PUBKEY_SIZE == mt_crypto::MLKEM_PUBLIC_KEY_SIZE);
    assert!(MT_MLKEM_SECKEY_SIZE == mt_crypto::MLKEM_SECRET_KEY_SIZE);
    assert!(MT_MLKEM_CT_SIZE == mt_crypto::MLKEM_CIPHERTEXT_SIZE);
    assert!(MT_MLKEM_SS_SIZE == mt_crypto::MLKEM_SHARED_SECRET_SIZE);
    assert!(MT_MLKEM_SEED_LEN == mt_crypto::MLKEM_SEED_SIZE);
    assert!(MT_ACCOUNT_ID_LEN == mt_crypto::HASH_SIZE);
};

pub const MT_OK: i32 = 0;
pub const MT_ERR_NULL_PTR: i32 = -1;
pub const MT_ERR_INVALID_UTF8: i32 = -2;
pub const MT_ERR_MNEMONIC_WORD_COUNT: i32 = -3;
pub const MT_ERR_MNEMONIC_UNKNOWN_WORD: i32 = -4;
pub const MT_ERR_MNEMONIC_CHECKSUM: i32 = -5;
pub const MT_ERR_KEYGEN_FAILED: i32 = -6;
pub const MT_ERR_SIGN_FAILED: i32 = -7;
pub const MT_ERR_VERIFY_FAILED: i32 = -8;
pub const MT_ERR_BUFFER_TOO_SMALL: i32 = -9;
pub const MT_ERR_KDF_FAILED: i32 = -10;
pub const MT_ERR_ADDRESS_INVALID: i32 = -13;
pub const MT_ERR_KEM_FAILED: i32 = -11;
pub const MT_ERR_REPLAY: i32 = -12;
pub const MT_ERR_IO: i32 = -14;
pub const MT_ERR_DECODE: i32 = -15;
pub const MT_ERR_CSPRNG: i32 = -16;
pub const MT_ERR_ENTROPY_HEALTH: i32 = -17;
pub const MT_ERR_PANIC: i32 = -100;

#[inline]
#[cfg_attr(target_arch = "wasm32", allow(dead_code))]
fn guard<F: FnOnce() -> i32>(f: F) -> i32 {
    match std::panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(code) => code,
        Err(_) => MT_ERR_PANIC,
    }
}

// ── Base58Check text address (App spec §4.3) — SSOT for all clients.
// address = "mt" + Base58(account_id ‖ checksum), checksum = SHA-256(SHA-256(account_id))[0..4].
fn sha256d(b: &[u8]) -> [u8; 32] {
    let h1 = Sha256::digest(b);
    Sha256::digest(h1).into()
}

const B58_ALPHABET: &[u8; 58] = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

fn base58_encode(input: &[u8]) -> String {
    let zeros = input.iter().take_while(|&&b| b == 0).count();
    let mut digits: Vec<u8> = Vec::new();
    for &byte in input {
        let mut carry = byte as u32;
        for d in digits.iter_mut() {
            carry += (*d as u32) << 8;
            *d = (carry % 58) as u8;
            carry /= 58;
        }
        while carry > 0 {
            digits.push((carry % 58) as u8);
            carry /= 58;
        }
    }
    let mut out = String::with_capacity(zeros + digits.len());
    for _ in 0..zeros {
        out.push('1');
    }
    for &d in digits.iter().rev() {
        out.push(B58_ALPHABET[d as usize] as char);
    }
    out
}

fn base58_decode(s: &str) -> Option<Vec<u8>> {
    let mut bytes: Vec<u8> = Vec::new();
    for ch in s.bytes() {
        let val = B58_ALPHABET.iter().position(|&a| a == ch)? as u32;
        let mut carry = val;
        for b in bytes.iter_mut() {
            carry += (*b as u32) * 58;
            *b = (carry & 0xff) as u8;
            carry >>= 8;
        }
        while carry > 0 {
            bytes.push((carry & 0xff) as u8);
            carry >>= 8;
        }
    }
    let zeros = s.bytes().take_while(|&c| c == b'1').count();
    let mut out = vec![0u8; zeros];
    out.extend(bytes.iter().rev());
    Some(out)
}

pub fn account_id_to_address(account_id: &[u8; MT_ACCOUNT_ID_LEN]) -> String {
    let cs = sha256d(account_id);
    let mut payload = Vec::with_capacity(MT_ACCOUNT_ID_LEN + 4);
    payload.extend_from_slice(account_id);
    payload.extend_from_slice(&cs[0..4]);
    format!("mt{}", base58_encode(&payload))
}

pub fn address_to_account_id(address: &str) -> Option<[u8; MT_ACCOUNT_ID_LEN]> {
    let body = address.strip_prefix("mt")?;
    let decoded = base58_decode(body)?;
    if decoded.len() != MT_ACCOUNT_ID_LEN + 4 {
        return None;
    }
    let (id, cs) = decoded.split_at(MT_ACCOUNT_ID_LEN);
    let expect = sha256d(id);
    if cs != &expect[0..4] {
        return None;
    }
    let mut out = [0u8; MT_ACCOUNT_ID_LEN];
    out.copy_from_slice(id);
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version_set() {
        assert_eq!(ABI_VERSION, 1);
    }

    #[test]
    fn base58_known_and_roundtrip() {
        assert_eq!(base58_encode(&[0, 0, 0]), "111");
        assert_eq!(base58_encode(&[1]), "2");
        for input in [
            vec![0u8; 36],
            vec![1, 2, 3, 4, 5],
            (0u8..36).collect::<Vec<_>>(),
        ] {
            assert_eq!(base58_decode(&base58_encode(&input)).unwrap(), input);
        }
    }

    #[test]
    fn address_roundtrip_and_checksum() {
        let id = [0xABu8; 32];
        let addr = account_id_to_address(&id);
        assert!(addr.starts_with("mt"));
        assert_eq!(address_to_account_id(&addr), Some(id));
        let mut chars: Vec<char> = addr.chars().collect();
        let last = chars.len() - 1;
        chars[last] = if chars[last] == 'z' { 'y' } else { 'z' };
        let tampered: String = chars.into_iter().collect();
        assert_eq!(address_to_account_id(&tampered), None);
    }

    #[test]
    fn constants_match_workspace() {
        assert_eq!(MT_MASTER_SEED_LEN, mt_mnemonic::MASTER_SEED_LEN);
        assert_eq!(MT_MLDSA_SEED_LEN, mt_mnemonic::MLDSA_SEED_LEN);
        assert_eq!(MT_MLDSA_PUBKEY_SIZE, mt_crypto::PUBLIC_KEY_SIZE);
        assert_eq!(MT_MLDSA_SECKEY_SIZE, mt_crypto::SECRET_KEY_SIZE);
        assert_eq!(MT_MLDSA_SIG_SIZE, mt_crypto::SIGNATURE_SIZE);
        assert_eq!(MT_MLKEM_SEED_LEN, mt_crypto::MLKEM_SEED_SIZE);
        assert_eq!(MT_MLKEM_PUBKEY_SIZE, mt_crypto::MLKEM_PUBLIC_KEY_SIZE);
        assert_eq!(MT_MLKEM_SECKEY_SIZE, mt_crypto::MLKEM_SECRET_KEY_SIZE);
        assert_eq!(MT_MLKEM_CT_SIZE, mt_crypto::MLKEM_CIPHERTEXT_SIZE);
        assert_eq!(MT_MLKEM_SS_SIZE, mt_crypto::MLKEM_SHARED_SECRET_SIZE);
    }
}

#[cfg(test)]
mod kat_address {
    #[test]
    fn history_key_kat() {
        let ent = [0x55u8; 32];
        let mut out = [0u8; 32];
        let rc = unsafe { crate::ffi_c::mt_history_key(ent.as_ptr(), out.as_mut_ptr()) };
        assert_eq!(rc, 0);
        assert_eq!(
            out.iter().map(|b| format!("{b:02x}")).collect::<String>(),
            "e6a7dc51003770589d9f731c1231c1523be7348c7769383875dd34bd6c578def"
        );
    }

    #[test]
    fn zero_entropy_address_kat() {
        // Reference vector: 32 zero bytes of entropy -> mnemonic -> account -> address.
        let m = mt_mnemonic::entropy_to_mnemonic(&[0u8; 32]);
        assert!(m.ends_with(" art"));
        let mc = std::ffi::CString::new(m).unwrap();
        let mut pk = vec![0u8; 1952];
        let mut sk = vec![0u8; 4032];
        let mut id = [0u8; 32];
        let rc = unsafe {
            crate::ffi_c::mt_account_from_mnemonic(
                mc.as_ptr(),
                pk.as_mut_ptr(),
                sk.as_mut_ptr(),
                id.as_mut_ptr(),
            )
        };
        assert_eq!(rc, 0);
        assert_eq!(
            id.iter().map(|b| format!("{b:02x}")).collect::<String>(),
            "9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21"
        );
        let addr = crate::account_id_to_address(&id);
        assert_eq!(addr, "mt2D4zg5S4qjjNLmuqLZsuS9rwMUoa47SgmQ7RQvkW7hfVmaRgfb");
        assert_eq!(crate::address_to_account_id(&addr), Some(id));
    }
}
