use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::identity::NodeError;

pub const CURRENT_WINDOW_FILE: &str = "current_window.bin";

// Layout v1 (16 байт):
//   [0..4]  magic = b"mtcw"
//   [4]     version = 1
//   [5..8]  reserved = 0 (выравнивание + future flags)
//   [8..16] window u64 LE
// Legacy v0 (8 байт): только window u64 LE без magic. На load auto-upgrade:
// распарсить как v0, следующий save запишет уже в v1.
const MAGIC: &[u8; 4] = b"mtcw";
const VERSION: u8 = 1;
const FILE_SIZE_V1: usize = 16;
const FILE_SIZE_V0: usize = 8;

pub fn meta_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("meta")
}

pub fn current_window_path(data_dir: &Path) -> PathBuf {
    meta_dir(data_dir).join(CURRENT_WINDOW_FILE)
}

pub fn load_current_window(data_dir: &Path) -> Result<u64, NodeError> {
    let path = current_window_path(data_dir);
    if !path.exists() {
        return Ok(0);
    }
    let bytes = fs::read(&path)?;
    match bytes.len() {
        FILE_SIZE_V1 => {
            if &bytes[0..4] != MAGIC.as_slice() {
                return Err(NodeError::InvalidMagic);
            }
            if bytes[4] != VERSION {
                return Err(NodeError::UnsupportedVersion(bytes[4]));
            }
            let mut buf = [0u8; 8];
            buf.copy_from_slice(&bytes[8..16]);
            Ok(u64::from_le_bytes(buf))
        },
        FILE_SIZE_V0 => {
            // Legacy без magic. Парсим как u64 LE; следующий save запишет v1.
            let mut buf = [0u8; 8];
            buf.copy_from_slice(&bytes);
            Ok(u64::from_le_bytes(buf))
        },
        actual => Err(NodeError::CorruptedSize {
            expected: FILE_SIZE_V1,
            actual,
        }),
    }
}

pub fn save_current_window(data_dir: &Path, window: u64) -> Result<(), NodeError> {
    fs::create_dir_all(meta_dir(data_dir))?;
    let path = current_window_path(data_dir);
    let tmp = path.with_extension("bin.tmp");
    let mut bytes = [0u8; FILE_SIZE_V1];
    bytes[0..4].copy_from_slice(MAGIC);
    bytes[4] = VERSION;
    bytes[8..16].copy_from_slice(&window.to_le_bytes());
    fs::write(&tmp, bytes)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

pub fn ensure_current_window_initialized(data_dir: &Path) -> Result<u64, NodeError> {
    let path = current_window_path(data_dir);
    if path.exists() {
        return load_current_window(data_dir);
    }
    save_current_window(data_dir, 0)?;
    Ok(0)
}

#[allow(dead_code)]
fn _io_to_local(e: io::Error) -> NodeError {
    NodeError::Io(e)
}
