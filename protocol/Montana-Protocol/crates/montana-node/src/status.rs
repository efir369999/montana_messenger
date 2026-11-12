// CNS-20: an operator reads the running process, never a persisted verdict from an earlier run.
// This local socket carries no network object and grants no consensus authority.
use crate::say::{PulseStatus, Verdict};
use crate::Machine;
use std::fs::OpenOptions;
use std::io::{Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

pub struct Server {
    // Keep the very owner of the directory lock alive until the endpoint is shut.
    _owner: Arc<Machine>,
    at: PathBuf,
    stop: Arc<AtomicBool>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl Server {
    pub fn open(data: &Path, owner: Arc<Machine>) -> std::io::Result<Self> {
        // Keep the pathname short on macOS too. A fresh owner-only directory means a crashed
        // process's socket is never reused. Retained endpoints are inert after their process exits.
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(std::io::Error::other)?
            .as_nanos();
        let directory = PathBuf::from(format!("/tmp/mt-pulse-{}-{nonce}", std::process::id()));
        std::fs::DirBuilder::new().mode(0o700).create(&directory)?;
        let at = directory.join("door");
        let listener = UnixListener::bind(&at)?;
        let mut locator = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(data.join("pulse-status"))?;
        writeln!(locator, "{}", at.display())?;
        let counts = owner.counts();
        let stop = Arc::new(AtomicBool::new(false));
        let stopping = Arc::clone(&stop);
        let thread = std::thread::spawn(move || {
            while let Ok((mut stream, _)) = listener.accept() {
                if stopping.load(Ordering::Acquire) {
                    return;
                }
                // The reader configures its budget before asking. On macOS setting a socket
                // timeout after its peer already closed can return EINVAL.
                // Reuse the wire's existing I/O budget; no freshness threshold or new polling.
                let _ = stream.set_write_timeout(Some(std::time::Duration::from_secs(
                    mt_net::PATIENCE_SECONDS,
                )));
                if stream
                    .set_read_timeout(Some(std::time::Duration::from_secs(
                        mt_net::PATIENCE_SECONDS,
                    )))
                    .is_err()
                {
                    continue;
                }
                let mut request = [0u8; 1];
                if stream.read_exact(&mut request).is_err() || request != *b"?" {
                    continue;
                }
                let status = counts.status().unwrap_or(PulseStatus::Stalled {
                    on: Verdict::NoDiagnostics,
                    asking: 0,
                    refused: 0,
                });
                let _ = writeln!(stream, "{status}");
            }
        });
        Ok(Self {
            _owner: owner,
            at,
            stop,
            thread: Some(thread),
        })
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Release);
        let _ = UnixStream::connect(&self.at); // Wake accept, without a polling thread.
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

// A read never takes the store's lock, not even for an instant (issue #21, F3): a reader that
// took it while no node held it would make a node starting in that instant refuse its own store.
// The proof that the owner lives is the endpoint itself: only a `Server`, which holds the very
// `Machine` that holds the lock, answers it, and it stops answering when that owner goes.
pub fn read(data: &Path) -> Result<PulseStatus, Verdict> {
    let absent = |_| Verdict::NoDiagnostics;
    let locator = std::fs::read_to_string(data.join("pulse-status")).map_err(absent)?;
    let mut stream = UnixStream::connect(locator.trim()).map_err(absent)?;
    stream
        .set_read_timeout(Some(std::time::Duration::from_secs(
            mt_net::PATIENCE_SECONDS,
        )))
        .map_err(absent)?;
    stream.write_all(b"?").map_err(absent)?;
    let mut text = String::new();
    // The longest line a reading writes: a wait, every number at its width.
    let bound = PulseStatus::Waiting {
        on: Verdict::NoDiagnostics,
        asking: u32::MAX,
        waited: u32::MAX,
        patience: u32::MAX,
        refused: u64::MAX,
    }
    .to_string()
    .len()
        + 1;
    stream
        .take(bound as u64)
        .read_to_string(&mut text)
        .map_err(absent)?;
    // A restart must not turn the old endpoint's last answer into the new process's status.
    if std::fs::read_to_string(data.join("pulse-status")).map_err(absent)? != locator {
        return Err(Verdict::NoDiagnostics);
    }
    match PulseStatus::parse(text.trim()) {
        Some(status) if status.on() != Some(Verdict::NoDiagnostics) => Ok(status),
        _ => Err(Verdict::NoDiagnostics),
    }
}
