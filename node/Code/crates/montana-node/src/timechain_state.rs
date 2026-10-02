use std::fs;
use std::path::{Path, PathBuf};

use mt_codec::domain;
use mt_crypto::{hash, Hash32};
use mt_genesis::genesis_params;

use crate::clock::meta_dir;
use crate::identity::NodeError;

pub const TIMECHAIN_FILE: &str = "timechain.bin";
const TIMECHAIN_MAGIC: &[u8; 4] = b"mttc";
const TIMECHAIN_VERSION: u8 = 2;
// magic(4) ver(1) pad(3) t_r(32) d(8) last_window(8) lottery_target(16) tau2_reveal_count(8)
const TIMECHAIN_SIZE: usize = 4 + 1 + 3 + 32 + 8 + 8 + 16 + 8;
const TIMECHAIN_SIZE_V1: usize = 4 + 1 + 3 + 32 + 8 + 8;

pub struct TimeChainState {
    pub t_r: Hash32,
    pub current_d: u64,
    pub last_window: u64,
    /// Текущий порог-цель розыгрыша (u128, спецификация «Калибровка target»).
    /// Генезис: u128::MAX — каждый активный узел кандидат до первой границы τ₂.
    pub lottery_target: u128,
    /// Счётчик зацементированных билетов в текущем отрезке τ₂.
    pub tau2_reveal_count: u64,
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
            lottery_target: u128::MAX,
            tau2_reveal_count: 0,
        });
    }
    let bytes = fs::read(&path)?;
    if &bytes[0..4] != TIMECHAIN_MAGIC.as_slice() {
        return Err(NodeError::InvalidMagic);
    }
    // v1 (без полей розыгрыша) читается с генезисными значениями полей —
    // совместимость со старым файлом; запись всегда v2.
    let (want, ver) = match bytes.get(4) {
        Some(1) => (TIMECHAIN_SIZE_V1, 1u8),
        Some(2) => (TIMECHAIN_SIZE, 2u8),
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
    let (lottery_target, tau2_reveal_count) = if ver == 2 {
        (
            u128::from_le_bytes(bytes[56..72].try_into().unwrap()),
            u64::from_le_bytes(bytes[72..80].try_into().unwrap()),
        )
    } else {
        (u128::MAX, 0)
    };
    Ok(TimeChainState {
        t_r,
        current_d,
        last_window,
        lottery_target,
        tau2_reveal_count,
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
    buf[56..72].copy_from_slice(&state.lottery_target.to_le_bytes());
    buf[72..80].copy_from_slice(&state.tau2_reveal_count.to_le_bytes());
    let tmp = path.with_extension("bin.tmp");
    fs::write(&tmp, &buf)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}
