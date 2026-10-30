//! The device-only vault (iOS E2EKeychain.setDeviceOnly -- AfterFirstUnlockThisDeviceOnly; Android DeviceVault -- a key in the
//! Keystore): a value sealed by Windows' own data protection (DPAPI) under the signed-in person's key, the sealed bytes in a
//! file of the app's LOCAL data folder, which no roaming profile carries. Another account of this machine, or the file
//! copied to another machine, opens nothing. Every write is read back: true only when the value is really there.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

#[derive(Clone)]
pub struct Vault {
    dir: PathBuf,
}

/// Bound into every seal beside the person's key: a value sealed by another program for the same person does not open here.
const ENTROPY: &[u8] = b"quest.montana.desktop vault 1";

impl Vault {
    pub fn at(dir: &Path) -> io::Result<Vault> {
        fs::create_dir_all(dir)?;
        Ok(Vault { dir: dir.to_path_buf() })
    }

    /// The vault's own folder (the keeping lays the parts it holds for others beside it).
    pub fn dir(&self) -> &Path {
        &self.dir
    }

    fn file(&self, name: &str) -> PathBuf {
        // names are the app's own constants; nothing a person types becomes a path
        debug_assert!(name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.'));
        self.dir.join(format!("{name}.sealed"))
    }

    pub fn set(&self, name: &str, value: &[u8]) -> bool {
        let Some(sealed) = dpapi::seal(value) else { return false };
        let path = self.file(name);
        // a write of its own: two writers of one value never share the file laid aside (they once did, and one could rename
        // the other's half-written bytes into place)
        static WRITES: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let n = WRITES.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let tmp = path.with_extension(format!("tmp{}-{n}", std::process::id()));
        if fs::write(&tmp, &sealed).is_err() || fs::rename(&tmp, &path).is_err() {
            let _ = fs::remove_file(&tmp);
            return false;
        }
        self.get(name).as_deref() == Some(value)
    }

    pub fn get(&self, name: &str) -> Option<Vec<u8>> {
        dpapi::unseal(&fs::read(self.file(name)).ok()?)
    }

    pub fn has(&self, name: &str) -> bool {
        self.file(name).exists()
    }

    pub fn delete(&self, name: &str) {
        let _ = fs::remove_file(self.file(name));
    }

    /// AN UNREADABLE VALUE IS NOT AN ABSENT ONE (the owner's word 24.10.2026: no loss of data): its sealed bytes are moved aside
    /// under a name of their own, never written over, and the value then reads as absent; `asides` finds them again.
    pub fn lay_aside(&self, name: &str) -> bool {
        let ms = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0);
        fs::rename(self.file(name), self.file(&format!("{name}.aside{ms}"))).is_ok()
    }

    /// The values of a name laid aside, oldest first (their names, as `get` reads them).
    pub fn asides(&self, name: &str) -> Vec<String> {
        let head = format!("{name}.aside");
        let mut found: Vec<String> = fs::read_dir(&self.dir).into_iter().flatten().flatten()
            .filter_map(|e| e.file_name().to_str()?.strip_suffix(".sealed").map(str::to_string))
            .filter(|n| n.strip_prefix(&head).is_some_and(|ms| !ms.is_empty() && ms.chars().all(|c| c.is_ascii_digit())))
            .collect();
        found.sort();
        found
    }
}

#[cfg(windows)]
mod dpapi {
    use super::ENTROPY;
    use windows_sys::Win32::Foundation::LocalFree;
    use windows_sys::Win32::Security::Cryptography::{
        CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
    };

    fn blob(b: &[u8]) -> CRYPT_INTEGER_BLOB {
        CRYPT_INTEGER_BLOB { cbData: b.len() as u32, pbData: b.as_ptr() as *mut u8 }
    }

    fn taken(out: CRYPT_INTEGER_BLOB) -> Vec<u8> {
        // SAFETY: DPAPI filled out with cbData bytes it allocated with LocalAlloc; copied, then freed once
        let v = unsafe { std::slice::from_raw_parts(out.pbData, out.cbData as usize) }.to_vec();
        unsafe { LocalFree(out.pbData as _) };
        v
    }

    pub fn seal(value: &[u8]) -> Option<Vec<u8>> {
        let (input, entropy) = (blob(value), blob(ENTROPY));
        let mut out = CRYPT_INTEGER_BLOB { cbData: 0, pbData: std::ptr::null_mut() };
        // SAFETY: the blobs point at live slices for the call; no prompt, no description
        let ok = unsafe {
            CryptProtectData(&input, std::ptr::null(), &entropy, std::ptr::null(), std::ptr::null(), CRYPTPROTECT_UI_FORBIDDEN, &mut out)
        };
        (ok != 0).then(|| taken(out))
    }

    pub fn unseal(sealed: &[u8]) -> Option<Vec<u8>> {
        let (input, entropy) = (blob(sealed), blob(ENTROPY));
        let mut out = CRYPT_INTEGER_BLOB { cbData: 0, pbData: std::ptr::null_mut() };
        // SAFETY: as in seal
        let ok = unsafe {
            CryptUnprotectData(&input, std::ptr::null_mut(), &entropy, std::ptr::null(), std::ptr::null(), CRYPTPROTECT_UI_FORBIDDEN, &mut out)
        };
        (ok != 0).then(|| taken(out))
    }
}

#[cfg(not(windows))]
mod dpapi {
    // Montana for Windows seals with Windows' own protection; elsewhere the app is not built
    pub fn seal(_: &[u8]) -> Option<Vec<u8>> { None }
    pub fn unseal(_: &[u8]) -> Option<Vec<u8>> { None }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("montana-vault-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        d
    }

    #[test]
    fn a_value_is_sealed_read_back_and_never_lies_in_the_clear() {
        let d = temp("roundtrip");
        let v = Vault::at(&d).unwrap();
        assert!(v.set("probe", b"abandon ability able"));
        assert_eq!(v.get("probe").as_deref(), Some(&b"abandon ability able"[..]));
        let raw = fs::read(d.join("probe.sealed")).unwrap();
        assert!(!raw.windows(7).any(|w| w == b"abandon"), "the file holds the words in the clear");
        v.delete("probe");
        assert!(!v.has("probe") && v.get("probe").is_none());
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn a_spoiled_file_opens_nothing() {
        let d = temp("spoiled");
        let v = Vault::at(&d).unwrap();
        assert!(v.set("probe", b"value"));
        let mut raw = fs::read(d.join("probe.sealed")).unwrap();
        let last = raw.len() - 1;
        raw[last] ^= 0x55;
        fs::write(d.join("probe.sealed"), raw).unwrap();
        assert!(v.get("probe").is_none());
        let _ = fs::remove_dir_all(&d);
    }
}
