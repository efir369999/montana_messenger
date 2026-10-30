//! THE SINGLE SOURCE OF TRUTH of the identity (iOS MontanaSeed; Android Identity.kt MontanaSeed): the 24 words, in one
//! representation, in the device-only vault. Everything else is derived from them on use, through the core's own doors.
//! The words and the keys stay on this side: the window is told only whether a person sits here.

use crate::abi::{
    mt_generate_mnemonic, mt_mldsa_seed_for_role, mt_mnemonic_to_master_seed, mt_seed_keys, MT_MASTER_SEED_LEN,
    MT_MAX_MNEMONIC_BYTES, MT_MLDSA_PUBKEY_SIZE, MT_MLDSA_SECKEY_SIZE, MT_MLDSA_SEED_LEN, MT_OK,
};
use crate::vault::Vault;
use sha2::{Digest, Sha256};
use std::ffi::CString;

pub(crate) const MN: &str = "mt_active_mnemonic";
const TWIN: &str = "mt.twin.ref";

/// Why the core refused words (mt-bindings' error codes, as iOS reads them).
#[derive(Debug, PartialEq, Eq)]
pub enum Refused {
    WordCount,
    UnknownWord,
    Checksum,
    Storage,
    Core(i32),
}

fn refused(rc: i32) -> Refused {
    match rc {
        -3 => Refused::WordCount,
        -4 => Refused::UnknownWord,
        -5 => Refused::Checksum,
        other => Refused::Core(other),
    }
}

/// The words a person typed, as the core reads them: one space between words, lower case.
pub fn normal(words: &str) -> String {
    words.split_whitespace().map(|w| w.to_lowercase()).collect::<Vec<_>>().join(" ")
}

/// The root is drawn by the core, never by the app (iOS MontanaSeedKeys.generate): "the only door through which a
/// Montana identity is born".
pub fn generate() -> Result<String, Refused> {
    let mut buf = vec![0u8; MT_MAX_MNEMONIC_BYTES];
    let mut len = 0usize;
    // SAFETY: a live buffer of its stated capacity and a live length
    let rc = unsafe { mt_generate_mnemonic(buf.as_mut_ptr(), buf.len(), &mut len) };
    let words = (rc == MT_OK).then(|| String::from_utf8(buf[..len].to_vec()).ok()).flatten();
    buf.fill(0);
    words.ok_or(refused(rc))
}

/// Whether the core opens keys from these words (mt_seed_keys): the check of a typed seed before it is kept.
pub fn check(words: &str) -> Result<(), Refused> {
    let c = CString::new(normal(words)).map_err(|_| Refused::UnknownWord)?;
    let mut public = vec![0u8; MT_MLDSA_PUBKEY_SIZE];
    let mut secret = vec![0u8; MT_MLDSA_SECKEY_SIZE];
    // SAFETY: a NUL-terminated string and buffers of the sizes the door writes
    let rc = unsafe { mt_seed_keys(c.as_ptr(), public.as_mut_ptr(), secret.as_mut_ptr()) };
    secret.fill(0);
    if rc == MT_OK { Ok(()) } else { Err(refused(rc)) }
}

pub struct Seed {
    vault: Vault,
}

impl Seed {
    pub fn new(vault: Vault) -> Seed {
        Seed { vault }
    }

    pub fn mnemonic(&self) -> Option<String> {
        self.vault.get(MN).and_then(|b| String::from_utf8(b).ok()).filter(|s| !s.is_empty())
    }

    pub fn has_seed(&self) -> bool {
        self.mnemonic().is_some()
    }

    /// The words land in storage, checked by the core first and read back after; anything else is no identity.
    pub fn enter(&self, words: &str) -> Result<(), Refused> {
        let words = normal(words);
        check(&words)?;
        self.clear();
        if self.vault.set(MN, words.as_bytes()) { Ok(()) } else { Err(Refused::Storage) }
    }

    pub fn clear(&self) {
        self.vault.delete(MN);
        self.vault.delete(TWIN);
    }

    /// The person's own reference (iOS MontanaSeed.twin): the owner branch of the seed,
    /// mt_mldsa_seed_for_role(master, "mt-owner-key"), filed under the first sixteen bytes of its SHA-256 in hex. It never
    /// leaves the device.
    pub fn twin(&self) -> Option<String> {
        if let Some(t) = self.vault.get(TWIN).and_then(|b| String::from_utf8(b).ok()).filter(|s| !s.is_empty()) {
            return Some(t);
        }
        let reference = twin_of(&self.mnemonic()?)?;
        self.vault.set(TWIN, reference.as_bytes());
        Some(reference)
    }
}

/// The person's key for the author field of a letter (iOS MontanaQueueKeys.authorKey): mt_mldsa_seed_for_role(master,
/// "mt-letter-author"), the same on every device of the words and on none other.
pub fn author_key_of(words: &str) -> Option<Vec<u8>> {
    role_seed(words, b"mt-letter-author")
}

pub fn role_seed(words: &str, role: &[u8]) -> Option<Vec<u8>> {
    role_of_master(&master_of(words)?, role)
}

/// The master seed of the words (iOS MontanaQueueKeys.masterSeed), wiped when it goes.
pub struct Master([u8; MT_MASTER_SEED_LEN]);
impl std::ops::Deref for Master {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        &self.0
    }
}
impl Drop for Master {
    fn drop(&mut self) {
        self.0.fill(0);
    }
}
pub fn master_of(words: &str) -> Option<Master> {
    let c = CString::new(normal(words)).ok()?;
    let mut master = Master([0u8; MT_MASTER_SEED_LEN]);
    // SAFETY: a NUL-terminated string and a 64-byte buffer
    (unsafe { mt_mnemonic_to_master_seed(c.as_ptr(), master.0.as_mut_ptr()) } == MT_OK).then_some(master)
}

/// A branch of the master seed (HKDF-Expand(master, role, 32), the core's one road for every branch).
pub fn role_of_master(master: &[u8], role: &[u8]) -> Option<Vec<u8>> {
    if master.len() != MT_MASTER_SEED_LEN {
        return None;
    }
    let mut out = vec![0u8; MT_MLDSA_SEED_LEN];
    // SAFETY: the 64-byte master, the role's bytes and a 32-byte buffer
    let rc = unsafe { mt_mldsa_seed_for_role(master.as_ptr(), role.as_ptr(), role.len(), out.as_mut_ptr()) };
    (rc == MT_OK).then_some(out)
}

pub fn twin_of(words: &str) -> Option<String> {
    let c = CString::new(normal(words)).ok()?;
    let mut master = [0u8; MT_MASTER_SEED_LEN];
    // SAFETY: a NUL-terminated string and a 64-byte buffer
    if unsafe { mt_mnemonic_to_master_seed(c.as_ptr(), master.as_mut_ptr()) } != MT_OK {
        return None;
    }
    let role = b"mt-owner-key";
    let mut owner = [0u8; MT_MLDSA_SEED_LEN];
    // SAFETY: the 64-byte master, the role's bytes and a 32-byte buffer
    let rc = unsafe { mt_mldsa_seed_for_role(master.as_ptr(), role.as_ptr(), role.len(), owner.as_mut_ptr()) };
    master.fill(0);
    if rc != MT_OK {
        return None;
    }
    let digest = Sha256::digest(owner);
    owner.fill(0);
    Some(digest[..16].iter().map(|b| format!("{b:02x}")).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seed(name: &str) -> (Seed, std::path::PathBuf) {
        let d = std::env::temp_dir().join(format!("montana-seed-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        (Seed::new(Vault::at(&d).unwrap()), d)
    }

    #[test]
    fn a_new_identity_is_born_kept_and_read_back_with_its_twin() {
        let (s, d) = seed("born");
        assert!(!s.has_seed());
        let words = generate().unwrap();
        assert_eq!(words.split(' ').count(), 24);
        s.enter(&words).unwrap();
        assert_eq!(s.mnemonic().as_deref(), Some(words.as_str()));
        let twin = s.twin().unwrap();
        assert_eq!(twin.len(), 32);
        assert_eq!(twin_of(&words).as_deref(), Some(twin.as_str()));   // derived again, the same: it hangs on the words alone
        s.clear();
        assert!(!s.has_seed());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn typed_words_are_taken_in_any_case_and_spacing_and_wrong_ones_refused() {
        let (s, d) = seed("typed");
        let words = generate().unwrap();
        let typed = format!("  {}  ", words.to_uppercase().replace(' ', "   "));
        s.enter(&typed).unwrap();
        assert_eq!(s.mnemonic().as_deref(), Some(words.as_str()));
        let mut wrong: Vec<&str> = words.split(' ').collect();
        assert_eq!(check(&wrong[..23].join(" ")), Err(Refused::WordCount));
        wrong[5] = "montanaxyz";
        assert_eq!(check(&wrong.join(" ")), Err(Refused::UnknownWord));
        // two words swapped keep every word known and break the checksum -- but for one in 256 swaps, which pass
        let swaps: Vec<Result<(), Refused>> = (1..8).map(|i| {
            let mut w: Vec<&str> = words.split(' ').collect();
            w.swap(0, i);
            check(&w.join(" "))
        }).collect();
        assert!(swaps.contains(&Err(Refused::Checksum)), "{swaps:?}");
        let _ = std::fs::remove_dir_all(&d);
    }
}
