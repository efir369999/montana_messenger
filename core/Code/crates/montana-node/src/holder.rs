//! The holder of a data directory (issue #21 K4). A running `start` keeps an exclusive `flock` on
//! the directory itself for the life of its process, and `status` reads whether one is held. The
//! lock is taken on the directory, so it writes nothing into the store, and the kernel drops it
//! when the process ends however it ends, so a node that died leaves no lock behind.

use std::fs::File;
use std::os::unix::io::AsRawFd;
use std::path::Path;
use std::time::{Duration, Instant};

use crate::identity::NodeError;

/// What `start` says when another running node holds its data directory.
pub const HELD_BY_ANOTHER: &str = "the data directory is held by another running node";

/// The exclusive lock of a running node on its data directory; dropped with the process.
pub struct Holder {
    _dir: File,
}

// A status probe holds its shared lock for the length of one call (`is_held`), so a start that
// meets one waits it out; a running node does not let go within the second.
const A_PROBE_IS_OUTLASTED: Duration = Duration::from_secs(1);

/// Takes the data directory for this process, or refuses while another running node holds it.
pub fn hold(data_dir: &Path) -> Result<Holder, NodeError> {
    let dir = File::open(data_dir)?;
    let since = Instant::now();
    loop {
        if try_lock(&dir, libc::LOCK_EX)? {
            return Ok(Holder { _dir: dir });
        }
        if since.elapsed() >= A_PROBE_IS_OUTLASTED {
            return Err(NodeError::InvalidArguments(HELD_BY_ANOTHER.into()));
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

/// Whether a running node holds `data_dir`. A shared lock is tried without waiting and let go at
/// once; nothing of the store is read or written.
pub fn is_held(data_dir: &Path) -> Result<bool, NodeError> {
    let dir = File::open(data_dir)?;
    Ok(!try_lock(&dir, libc::LOCK_SH)?)
}

// `flock` without waiting: true when taken, false when another open file holds a conflicting lock.
fn try_lock(file: &File, kind: libc::c_int) -> Result<bool, NodeError> {
    // SAFETY: flock reads a file descriptor that `file` owns for the length of the call.
    if unsafe { libc::flock(file.as_raw_fd(), kind | libc::LOCK_NB) } == 0 {
        return Ok(true);
    }
    let e = std::io::Error::last_os_error();
    if e.kind() == std::io::ErrorKind::WouldBlock {
        Ok(false)
    } else {
        Err(NodeError::Io(e))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Refuses a holder that does not exclude a second one, a lock that outlives its holder, and a
    // probe that leaves anything in the store.
    #[test]
    fn one_holder_at_a_time_and_none_after_it_ends() {
        let dir = std::env::temp_dir().join(format!("montana-node-holder-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        assert!(!is_held(&dir).unwrap());
        let holder = hold(&dir).expect("an unheld directory is taken");
        assert!(is_held(&dir).unwrap());
        assert!(
            is_held(&dir).unwrap(),
            "a probe does not release the holder"
        );
        match hold(&dir) {
            Err(NodeError::InvalidArguments(what)) => assert_eq!(what, HELD_BY_ANOTHER),
            _ => panic!("a second holder of a held directory"),
        }
        drop(holder);
        assert!(!is_held(&dir).unwrap());
        drop(hold(&dir).expect("taken again once let go"));
        assert_eq!(
            std::fs::read_dir(&dir).unwrap().count(),
            0,
            "the lock wrote into the store"
        );
        std::fs::remove_dir(&dir).unwrap();
    }
}
