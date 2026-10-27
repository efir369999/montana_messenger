use std::fs;
use std::path::{Path, PathBuf};

use mt_codec::domain;
use mt_crypto::{hash, Hash32};
use mt_genesis::genesis_params;

use crate::clock::meta_dir;
use crate::identity::NodeError;

pub const TIMECHAIN_FILE: &str = "timechain.bin";
const TIMECHAIN_MAGIC: &[u8; 4] = b"mttc";
const TIMECHAIN_VERSION: u8 = 1;
// magic(4) ver(1) pad(3) t_r(32) d(8) last_window(8)
const TIMECHAIN_SIZE: usize = 4 + 1 + 3 + 32 + 8 + 8;
// Version 2 appended lottery_target(16) and tau2_reveal_count(8). The lottery
// threshold and its counter are removed (issue #18), so a v2 record is read
// without them and every record is written as v1 again.
const TIMECHAIN_SIZE_V2: usize = TIMECHAIN_SIZE + 16 + 8;

pub struct TimeChainState {
    pub t_r: Hash32,
    pub current_d: u64,
    pub last_window: u64,
}

pub fn timechain_path(data_dir: &Path) -> PathBuf {
    meta_dir(data_dir).join(TIMECHAIN_FILE)
}

pub fn genesis_t_r() -> Hash32 {
    hash(domain::TIMECHAIN, &[&[0u8; 32]])
}

pub fn load_or_init_timechain(data_dir: &Path) -> Result<TimeChainState, NodeError> {
    let path = timechain_path(data_dir);
    if !path.exists() {
        let params = genesis_params();
        return Ok(TimeChainState {
            t_r: genesis_t_r(),
            current_d: params.d0,
            last_window: 0,
        });
    }
    let bytes = fs::read(&path)?;
    // A record shorter than its magic is refused, not sliced.
    match bytes.get(0..4) {
        Some(magic) if magic == TIMECHAIN_MAGIC.as_slice() => {},
        Some(_) => return Err(NodeError::InvalidMagic),
        None => {
            return Err(NodeError::CorruptedSize {
                expected: TIMECHAIN_SIZE,
                actual: bytes.len(),
            })
        },
    }
    // v2 carries the removed lottery fields after the v1 layout; they are not read.
    let want = match bytes.get(4) {
        Some(1) => TIMECHAIN_SIZE,
        Some(2) => TIMECHAIN_SIZE_V2,
        Some(v) => return Err(NodeError::UnsupportedVersion(*v)),
        None => {
            return Err(NodeError::CorruptedSize {
                expected: TIMECHAIN_SIZE,
                actual: bytes.len(),
            })
        },
    };
    if bytes.len() != want {
        return Err(NodeError::CorruptedSize {
            expected: want,
            actual: bytes.len(),
        });
    }
    let mut t_r = [0u8; 32];
    t_r.copy_from_slice(&bytes[8..40]);
    let current_d = u64::from_le_bytes(bytes[40..48].try_into().unwrap());
    let last_window = u64::from_le_bytes(bytes[48..56].try_into().unwrap());
    Ok(TimeChainState {
        t_r,
        current_d,
        last_window,
    })
}

pub fn save_timechain(data_dir: &Path, state: &TimeChainState) -> Result<(), NodeError> {
    fs::create_dir_all(meta_dir(data_dir))?;
    let path = timechain_path(data_dir);
    let mut buf = vec![0u8; TIMECHAIN_SIZE];
    buf[0..4].copy_from_slice(TIMECHAIN_MAGIC);
    buf[4] = TIMECHAIN_VERSION;
    buf[8..40].copy_from_slice(&state.t_r);
    buf[40..48].copy_from_slice(&state.current_d.to_le_bytes());
    buf[48..56].copy_from_slice(&state.last_window.to_le_bytes());
    let tmp = path.with_extension("bin.tmp");
    fs::write(&tmp, &buf)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}
