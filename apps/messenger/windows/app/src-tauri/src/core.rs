//! The core as the window sees it: the ABI's version and the measures of this machine's entropy sources, the
//! things the core itself says a person is entitled to see. Identity, keys and words never come through here.

use crate::abi::{mt_abi_version, mt_entropy_min_live, mt_entropy_sources, MT_OK};
use serde::Serialize;

/// The sources in the order the core measures them (mt-mnemonic measure_sources, SourceReport::TOTAL = 6). The
/// comment above mt_entropy_sources in ffi_c.rs still speaks of seven with a CPU instruction; the code measures these.
const SOURCES: [&str; 6] = ["OS CSPRNG", "jitter", "memory", "quartz", "scheduler", "timer"];

#[derive(Serialize, Debug)]
pub struct Source {
    pub name: &'static str,
    pub samples: u16,
    pub distinct: u16,
    pub max_repeat: u16,
    pub alive: bool,
}

#[derive(Serialize, Debug)]
pub struct CoreInfo {
    pub abi: u32,
    pub sources: Vec<Source>,
    pub live: usize,
    pub min_live: i32,
    pub error: Option<i32>,
}

pub fn info() -> CoreInfo {
    let mut buf = [0u8; 7 * 8]; // 7 bytes a source; room for more than the core has today
    let mut len = 0usize;
    // SAFETY: buf is a live buffer of buf.len() bytes and len a live usize, as the door asks.
    let rc = unsafe { mt_entropy_sources(buf.as_mut_ptr(), buf.len(), &mut len) };
    let sources: Vec<Source> = if rc == MT_OK {
        buf[..len]
            .chunks_exact(7)
            .zip(SOURCES)
            .map(|(r, name)| Source {
                name,
                samples: u16::from_le_bytes([r[0], r[1]]),
                distinct: u16::from_le_bytes([r[2], r[3]]),
                max_repeat: u16::from_le_bytes([r[4], r[5]]),
                alive: r[6] != 0,
            })
            .collect()
    } else {
        Vec::new()
    };
    CoreInfo {
        // SAFETY: the door takes nothing and returns a number
        abi: unsafe { mt_abi_version() },
        live: sources.iter().filter(|s| s.alive).count(),
        sources,
        // SAFETY: as above
        min_live: unsafe { mt_entropy_min_live() },
        error: (rc != MT_OK).then_some(rc),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::abi::{mt_generate_mnemonic, mt_seed_keys, ABI_VERSION, MT_MAX_MNEMONIC_BYTES, MT_MLDSA_PUBKEY_SIZE, MT_MLDSA_SECKEY_SIZE};

    #[test]
    fn the_window_sees_every_measured_source_and_enough_of_them_alive() {
        let i = info();
        assert_eq!(i.abi, ABI_VERSION, "the DLL is not the core this app was written for");
        assert_eq!(i.error, None);
        assert_eq!(i.sources.len(), SOURCES.len());
        assert!(i.live as i32 >= i.min_live, "{} live of {} needed: {:?}", i.live, i.min_live, i.sources);
    }

    #[test]
    fn an_identity_is_born_on_this_machine_through_the_cores_own_door() {
        // the 24 words and the keys stay in this test, as they will stay in the Rust side of the app
        let mut words = [0u8; MT_MAX_MNEMONIC_BYTES];
        let mut len = 0usize;
        // SAFETY: live buffers of the stated sizes
        assert_eq!(unsafe { mt_generate_mnemonic(words.as_mut_ptr(), words.len(), &mut len) }, MT_OK);
        assert_eq!(std::str::from_utf8(&words[..len]).unwrap().split(' ').count(), 24);
        let mut public = vec![0u8; MT_MLDSA_PUBKEY_SIZE];
        let mut secret = vec![0u8; MT_MLDSA_SECKEY_SIZE];
        // SAFETY: words is NUL-terminated by the door; the key buffers are of the sizes the door writes
        let rc = unsafe { mt_seed_keys(words.as_ptr() as *const _, public.as_mut_ptr(), secret.as_mut_ptr()) };
        assert_eq!(rc, MT_OK);
        assert!(public.iter().any(|&b| b != 0));
    }
}
