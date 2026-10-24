// What a machine keeps between one start and the next. The set lays out the objects a machine
// holds and says nothing about how they reach a disk, so nothing here transcribes a rule of the
// set: what this crate owes is that a machine stopped at any instant starts again holding what it
// held, and never half of it.
//
// Three properties carry that, and each is held by construction rather than by care:
//
// **A write is whole or it never happened.** Every value goes to a file of its own beside the one
// it replaces, is flushed to the disk, and is then renamed onto it — so a machine losing power
// mid-write starts again on the value that stood before, and a reader never sees a prefix of a
// value that was being written.
//
// **The head follows what it names.** A proposal is stored before the head that points at it moves,
// so the two orders a crash can leave are "a proposal nothing points at", which costs a file, and
// never "a head pointing at a proposal that is not there", which would be a machine claiming a
// window it cannot show. Opening refuses the second outright rather than repairing it.
//
// **A secret is drawn once.** A machine that redrew its own secret would be a second machine
// wearing the name of the first, and everything the first was known by — the links it holds, the
// points it stands at, the record that names it — would be unreachable with nothing saying so. The
// door refuses a second drawing rather than overwriting.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use zeroize::Zeroizing;

mt_codec::constants! {
    STORE:
    /// The secret a machine draws for itself on its first start. The set gives it no row: what it
    /// is the width of is the answering key it seeds, and that width is the one below.
    pub const SECRET_BYTES: usize = 32, code "the width of the secret a machine draws for itself, which this tree keeps and the set lays out nowhere";
    /// The window a head names, as an unsigned little-endian integer of the width every window of
    /// this protocol is written at.
    pub const HEAD_BYTES: usize = 8, code "the width a window number is written at on a disk of this tree, which is the width every layout of the set gives it";
    /// The permissions of the file holding a secret, on a system that has them.
    const SECRET_MODE: u32 = 0o600, code "the permissions of the file holding a machine's secret: its owner and nobody else";
}

#[derive(Debug, PartialEq, Eq)]
pub enum StoreError {
    // What the filesystem answered, with the path it answered about. The message is the operator's
    // and never a stranger's: nothing of this crate crosses a wire.
    Filesystem {
        at: String,
        said: String,
    },
    // Publication happened, but the directory durability barrier failed. The caller must not
    // report a definite rollback: readers already see the complete new value.
    CommitUncertain {
        at: String,
        said: String,
    },
    // A persisted directory is not silently relabelled after a change of protocol parameters.
    UnboundNetwork,
    WrongNetwork {
        expected: [u8; 32],
        found: [u8; 32],
    },
    UnpublishedNetwork,
    // A file of a width its value does not have. Refused before it is read, like every object of
    // this protocol.
    WrongLength {
        at: String,
        expected: usize,
        found: usize,
    },
    // A machine that already drew its secret, asked to draw a second.
    SecretStands,
    // A store another process holds open. One store, one process: every birth of a second writer is
    // owned here rather than raced at every door.
    HeldByAnother {
        at: String,
    },
    // A head naming a window whose proposal is not stored. The order of writing makes this the one
    // arrangement a crash cannot produce, so a store holding it was edited by something other than
    // this crate.
    HeadWithoutItsProposal {
        window: u64,
    },
}

fn said(at: &Path, e: std::io::Error) -> StoreError {
    StoreError::Filesystem {
        at: at.display().to_string(),
        said: e.to_string(),
    }
}

// The one door that puts bytes on a disk. The temporary stands beside the value it replaces rather
// than in a directory of the system, because a rename across two filesystems is a copy and a copy
// is not atomic.
//
// **A file is closed before a byte of it is written.** What a machine keeps is its own — its
// secret, what a person holds, the proposals it stands on — so the temporary is created with the
// permissions of its owner alone and never widened afterwards. Closing it after the write would
// leave a window in which the secret of a machine stands readable to everyone on that machine,
// and a window of that kind is not smaller for being brief: a reader waiting for it reads it.
fn write_whole(at: &Path, bytes: &[u8]) -> Result<(), StoreError> {
    write_complete(at, bytes, false)
}

fn write_complete(at: &Path, bytes: &[u8], only_once: bool) -> Result<(), StoreError> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SERIAL: AtomicU64 = AtomicU64::new(0);
    let directory = at.parent().unwrap_or(Path::new("."));
    let tick = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| said(at, std::io::Error::other(e)))?
        .as_nanos();
    let beside = at.with_extension(format!(
        "writing-{}-{tick}-{}",
        std::process::id(),
        SERIAL.fetch_add(1, Ordering::Relaxed)
    ));
    {
        let mut file = create_closed(&beside)?;
        file.write_all(bytes).map_err(|e| said(&beside, e))?;
        file.sync_all().map_err(|e| said(&beside, e))?;
    }
    if only_once {
        // Linking a fully flushed file publishes it only if the destination does not exist.
        // The private temporary is retained; no racing writer can replace the winning identity.
        fs::hard_link(&beside, at).map_err(|e| {
            if e.kind() == std::io::ErrorKind::AlreadyExists {
                StoreError::SecretStands
            } else {
                said(at, e)
            }
        })?;
    } else {
        fs::rename(&beside, at).map_err(|e| said(at, e))?;
    }
    let uncertain = |e: std::io::Error| StoreError::CommitUncertain {
        at: at.display().to_string(),
        said: e.to_string(),
    };
    fs::File::open(directory)
        .map_err(uncertain)?
        .sync_all()
        .map_err(uncertain)?;
    Ok(())
}

// The temporaries of exclusive openings left by a process that died between writing and linking,
// removed under the lock of the root. Nothing else of the root is touched.
fn sweep_dead_openings(root: &Path) -> Result<(), StoreError> {
    for entry in fs::read_dir(root).map_err(|e| said(root, e))? {
        let entry = entry.map_err(|e| said(root, e))?;
        let name = entry.file_name();
        if name.to_string_lossy().contains(".opening-") {
            let at = entry.path();
            fs::remove_file(&at).map_err(|e| said(&at, e))?;
        }
    }
    Ok(())
}

// A complete file linked into place only where none stands: the writer whose link lands is the one
// whose bytes stand, and every other learns so. The temporary is removed once the link landed or
// failed, since what it carried stands under the name or lost to what does; the directory is
// flushed so the name survives a loss of power.
fn publish_once(at: &Path, bytes: &[u8]) -> Result<bool, StoreError> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SERIAL: AtomicU64 = AtomicU64::new(0);
    let directory = at.parent().unwrap_or(Path::new("."));
    // The process and a serial make the temporary's name its own; the store reads no clock.
    let beside = at.with_extension(format!(
        "opening-{}-{}",
        std::process::id(),
        SERIAL.fetch_add(1, Ordering::Relaxed)
    ));
    {
        let mut file = create_closed(&beside)?;
        file.write_all(bytes).map_err(|e| said(&beside, e))?;
        file.sync_all().map_err(|e| said(&beside, e))?;
    }
    let landed = match fs::hard_link(&beside, at) {
        Ok(()) => true,
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => false,
        Err(e) => {
            let _ = fs::remove_file(&beside);
            return Err(said(at, e));
        }
    };
    fs::remove_file(&beside).map_err(|e| said(&beside, e))?;
    let uncertain = |e: std::io::Error| StoreError::CommitUncertain {
        at: at.display().to_string(),
        said: e.to_string(),
    };
    fs::File::open(directory)
        .map_err(uncertain)?
        .sync_all()
        .map_err(uncertain)?;
    Ok(landed)
}

// Exclusive creation refuses stale files and symlinks. Permissions are set on the creation
// itself, so no earlier file's bytes or permissions can be inherited by this write.
#[cfg(unix)]
fn create_closed(at: &Path) -> Result<fs::File, StoreError> {
    use std::os::unix::fs::OpenOptionsExt;
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(SECRET_MODE)
        .open(at)
        .map_err(|e| said(at, e))
}

#[cfg(not(unix))]
fn create_closed(at: &Path) -> Result<fs::File, StoreError> {
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(at)
        .map_err(|e| said(at, e))
}

// Fixed-size reading bounds network markers and signing locks before any allocation.
fn read_digest(at: &Path) -> Result<Option<[u8; 32]>, StoreError> {
    let mut file = match fs::File::open(at) {
        Ok(file) => file,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(said(at, e)),
    };
    let mut bytes = Vec::new();
    Read::by_ref(&mut file)
        .take(33)
        .read_to_end(&mut bytes)
        .map_err(|e| said(at, e))?;
    let bytes = of_width(at, bytes, 32)?;
    let mut value = [0; 32];
    value.copy_from_slice(&bytes);
    Ok(Some(value))
}

// What a secret is read through. The bytes of a file land in one allocation and that allocation is
// the wrapper that wipes: a value read into a plain vector would be the first place the secret of
// a machine stands, and nothing would ever wipe it.
fn read_secret(at: &Path) -> Result<Option<Zeroizing<Vec<u8>>>, StoreError> {
    match fs::read(at) {
        Ok(bytes) => Ok(Some(Zeroizing::new(bytes))),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(said(at, e)),
    }
}

fn read_whole(at: &Path) -> Result<Option<Vec<u8>>, StoreError> {
    match fs::read(at) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(said(at, e)),
    }
}

fn of_width(at: &Path, bytes: Vec<u8>, expected: usize) -> Result<Vec<u8>, StoreError> {
    if bytes.len() != expected {
        return Err(StoreError::WrongLength {
            at: at.display().to_string(),
            expected,
            found: bytes.len(),
        });
    }
    Ok(bytes)
}

// What a store keeps of a machine's points: for each window and point, the cells standing there in
// the order they were taken.
pub type CellsStanding = Vec<(u64, [u8; 16], Vec<Vec<u8>>)>;

pub struct Store {
    root: PathBuf,
    // The handle of the root directory, locked exclusively for the life of the store. **One store,
    // one process.** Two processes writing one store would race at every door that reads before it
    // writes — the number of the last window closed, the opening of a window's record after the
    // check that the window is not closed — and no door can own the birth of the second writer but
    // this one. The lock goes with the handle, so a store dropped releases it and a process that
    // died holds nothing.
    _held: fs::File,
}

impl Store {
    // Opening makes the tree of directories if it is not there, takes the lock of the root, and
    // answers with a store whose head, if it names a window, has that window's proposal beside it.
    pub fn open(root: impl AsRef<Path>) -> Result<Self, StoreError> {
        let root = root.as_ref().to_path_buf();
        let proposals = root.join("proposals");
        fs::create_dir_all(&proposals).map_err(|e| said(&proposals, e))?;
        let held = fs::File::open(&root).map_err(|e| said(&root, e))?;
        match held.try_lock() {
            Ok(()) => {}
            Err(fs::TryLockError::WouldBlock) => {
                return Err(StoreError::HeldByAnother {
                    at: root.display().to_string(),
                })
            }
            Err(fs::TryLockError::Error(e)) => return Err(said(&root, e)),
        }
        // **What a dead process left of an opening goes before anything is read.** The temporary of
        // an exclusive opening is named by the process and a serial, not by a clock, so a process
        // that fell between writing it and linking it leaves a name the next process draws again --
        // in a container the node is process one at every start -- and the opening of that record
        // would be refused for ever. The lock is held, so every such file in the root is a dead
        // process's; this process holds the root alone.
        sweep_dead_openings(&root)?;
        let store = Self { root, _held: held };
        store.check_network()?;
        if let Some(window) = store.head()? {
            if store.proposal(window)?.is_none() {
                return Err(StoreError::HeadWithoutItsProposal { window });
            }
        }
        Ok(store)
    }

    fn check_network(&self) -> Result<(), StoreError> {
        let expected =
            mt_state::tables::genesis_state_hash().ok_or(StoreError::UnpublishedNetwork)?;
        let at = self.root.join("genesis");
        if let Some(found) = read_digest(&at)? {
            return if found == expected {
                Ok(())
            } else {
                Err(StoreError::WrongNetwork { expected, found })
            };
        }
        // An empty directory may be initialized. An old value plane, identity, wallet or proposal
        // must go through an authenticated migration, which this interface does not invent.
        for entry in fs::read_dir(&self.root).map_err(|e| said(&self.root, e))? {
            let entry = entry.map_err(|e| said(&self.root, e))?;
            let name = entry.file_name();
            let name = name.to_string_lossy();
            let harmless = name.starts_with("genesis.writing-")
                || (name == "proposals"
                    && fs::read_dir(entry.path())
                        .map_err(|e| said(&entry.path(), e))?
                        .next()
                        .is_none());
            if !harmless {
                // Another opener may have published the binding after our first read.
                return match read_digest(&at)? {
                    Some(found) if found == expected => Ok(()),
                    Some(found) => Err(StoreError::WrongNetwork { expected, found }),
                    None => Err(StoreError::UnboundNetwork),
                };
            }
        }
        match write_complete(&at, &expected, true) {
            Ok(()) => Ok(()),
            Err(StoreError::SecretStands) => match read_digest(&at)? {
                Some(found) if found == expected => Ok(()),
                Some(found) => Err(StoreError::WrongNetwork { expected, found }),
                None => Err(StoreError::UnboundNetwork),
            },
            Err(error) => Err(error),
        }
    }

    fn secret_at(&self) -> PathBuf {
        self.root.join("identity")
    }

    fn head_at(&self) -> PathBuf {
        self.root.join("head")
    }

    fn proposal_at(&self, window: u64) -> PathBuf {
        // The name is the window in full width, so the order of the names is the order of the
        // windows and a directory listing needs no sorting rule of its own.
        self.root.join("proposals").join(format!("{window:020}"))
    }

    // The secret this machine drew, or nothing if it has not been born yet.
    pub fn secret(&self) -> Result<Option<Zeroizing<[u8; SECRET_BYTES]>>, StoreError> {
        let at = self.secret_at();
        let Some(bytes) = read_secret(&at)? else {
            return Ok(None);
        };
        if bytes.len() != SECRET_BYTES {
            return Err(StoreError::WrongLength {
                at: at.display().to_string(),
                expected: SECRET_BYTES,
                found: bytes.len(),
            });
        }
        let mut held = Zeroizing::new([0u8; SECRET_BYTES]);
        held.copy_from_slice(&bytes);
        Ok(Some(held))
    }

    // The one drawing. A machine that already holds a secret is refused rather than overwritten:
    // the first secret is what every acquaintance, every link and every point of this machine
    // stands on, and a second would make all of them unreachable in silence.
    pub fn bear_secret(&self, secret: &[u8; SECRET_BYTES]) -> Result<(), StoreError> {
        let at = self.secret_at();
        write_complete(&at, secret, true)?;
        self.close_the_file_to_others(&at)
    }

    // **What a machine holds of the agreement on one open window**: its attempt, its lock, its
    // valid name and every pledge it made, written before anything they govern is published, kept
    // through a restart, and let go when the window closes — so a machine holds one record for each
    // open window and never a history (Consensus, "What a machine holds of the agreement"). It took
    // the place of a signing lock kept for each window and never removed: the record carries what
    // that lock carried — the name this machine pledged — and the rest the agreement needs.
    fn agreement_at(&self, window: u64) -> PathBuf {
        self.root.join(format!("agreement-{window:020}"))
    }

    pub fn agreement(&self, window: u64) -> Result<Option<Vec<u8>>, StoreError> {
        read_whole(&self.agreement_at(window))
    }

    // **The first record of a window is written once and exclusively.** Two processes on one store
    // that both read nothing and both wrote would each believe its own name, and the one key of
    // this machine would pledge two names for one window — the first of the contradicting pairs.
    // So the opening links a complete file into place only where none stands, the door the secret
    // is drawn through, and where one stands already it answers with the bytes that stand, which
    // the caller compares with its own. The named wrong implementation: read-then-rename, under
    // which the last writer wins and both believe themselves.
    pub fn open_agreement(&self, window: u64, bytes: &[u8]) -> Result<Vec<u8>, StoreError> {
        let at = self.agreement_at(window);
        if publish_once(&at, bytes)? {
            return Ok(bytes.to_vec());
        }
        read_whole(&at)?.ok_or_else(|| {
            said(
                &at,
                std::io::Error::other("an agreement record that stood disappeared"),
            )
        })
    }

    // A later writing of the record of a window this process opened: whole, over the one before.
    pub fn put_agreement(&self, window: u64, bytes: &[u8]) -> Result<(), StoreError> {
        write_whole(&self.agreement_at(window), bytes)
    }

    // **The last window this machine closed**, one number and never a history: the record of a
    // closed window is let go, and this is what refuses that window to be opened again — a machine
    // that opened a closed window afresh could pledge a second name for it (Consensus, "What a
    // machine holds of the agreement"; "The way back": an honest machine preserves its pledges
    // across a restart). It is written before the record is dropped.
    fn closed_at(&self) -> PathBuf {
        self.root.join("closed")
    }

    pub fn closed(&self) -> Result<Option<u64>, StoreError> {
        let at = self.closed_at();
        let Some(bytes) = read_whole(&at)? else {
            return Ok(None);
        };
        let bytes = of_width(&at, bytes, HEAD_BYTES)?;
        let mut eight = [0u8; HEAD_BYTES];
        eight.copy_from_slice(&bytes);
        Ok(Some(u64::from_le_bytes(eight)))
    }

    // The number moves forward and never back: a window below the one already closed was closed
    // before it, and writing it again would say otherwise.
    pub fn put_closed(&self, window: u64) -> Result<(), StoreError> {
        if self.closed()?.is_some_and(|held| held > window) {
            return Ok(());
        }
        write_whole(&self.closed_at(), &window.to_le_bytes())
    }

    // The record of a window that closed, removed; a record that is not there is already gone.
    pub fn drop_agreement(&self, window: u64) -> Result<(), StoreError> {
        let at = self.agreement_at(window);
        match fs::remove_file(&at) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(said(&at, e)),
        }
    }

    #[cfg(unix)]
    fn close_the_file_to_others(&self, at: &Path) -> Result<(), StoreError> {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(at, fs::Permissions::from_mode(SECRET_MODE)).map_err(|e| said(at, e))
    }

    // A system without the permissions of a Unix file leaves the secret at whatever it grants by
    // default, and this crate says so rather than implying a protection it did not apply.
    #[cfg(not(unix))]
    fn close_the_file_to_others(&self, _at: &Path) -> Result<(), StoreError> {
        Ok(())
    }

    // What a person holds. It is secret exactly as the machine's own secret is — a note names its
    // owner to whoever reads it — so it goes through the same door and is closed to everyone but
    // its owner, and it is written whole like everything else here.
    fn notes_at(&self) -> PathBuf {
        self.root.join("notes")
    }

    pub fn notes(&self) -> Result<Zeroizing<Vec<u8>>, StoreError> {
        Ok(read_secret(&self.notes_at())?.unwrap_or_else(|| Zeroizing::new(Vec::new())))
    }

    pub fn put_notes(&self, bytes: &[u8]) -> Result<(), StoreError> {
        let at = self.notes_at();
        write_whole(&at, bytes)?;
        self.close_the_file_to_others(&at)
    }

    // A note handed from one person to another. What a payee needs of a note it was paid is the
    // value, the key it is paid to and the blinding factor of it — and the last of those is a
    // secret: whoever holds it and the key holds that note. So it is written to a file closed to
    // everyone but its owner and carried across as a file, never printed to a terminal where a
    // scrollback keeps it and never given on a command line where every other process reads it.
    pub fn put_handed_note(&self, at: &Path, bytes: &[u8]) -> Result<(), StoreError> {
        write_whole(at, bytes)?;
        self.close_the_file_to_others(at)
    }

    fn value_at(&self) -> PathBuf {
        self.root.join("value")
    }

    fn standing_at(&self) -> PathBuf {
        self.root.join("standing")
    }

    // **What a machine holds of its own standing**: the census windows it lived and the branch its
    // part walks in each of their cements. It is a secret of the machine exactly as its notes are a
    // secret of a person — the set publishes no standing, and a file readable to others would be
    // the one place a machine's weight stood in the open — so it goes through the same door and is
    // closed to everyone but its owner.
    pub fn standing(&self) -> Result<Zeroizing<Vec<u8>>, StoreError> {
        Ok(read_secret(&self.standing_at())?.unwrap_or_else(|| Zeroizing::new(Vec::new())))
    }

    pub fn put_standing(&self, bytes: &[u8]) -> Result<(), StoreError> {
        let at = self.standing_at();
        write_whole(&at, bytes)?;
        self.close_the_file_to_others(&at)
    }

    // **What a machine holds of the value plane, kept across a stop.** A note taken in one run is
    // spendable in the next only where the tree that gave it a position still stands, and a plane
    // that lived in memory alone made every note die with the run that created it — so a person
    // paid could hold a note their own machine could no longer prove a path for. It carries no
    // secret of anybody: commitments, nullifiers and roots are what the network publishes.
    pub fn value(&self) -> Result<Vec<u8>, StoreError> {
        Ok(read_whole(&self.value_at())?.unwrap_or_default())
    }

    pub fn put_value(&self, bytes: &[u8]) -> Result<(), StoreError> {
        write_whole(&self.value_at(), bytes)
    }

    pub fn head(&self) -> Result<Option<u64>, StoreError> {
        let at = self.head_at();
        let Some(bytes) = read_whole(&at)? else {
            return Ok(None);
        };
        let bytes = of_width(&at, bytes, HEAD_BYTES)?;
        let mut eight = [0u8; HEAD_BYTES];
        eight.copy_from_slice(&bytes);
        Ok(Some(u64::from_le_bytes(eight)))
    }

    // **What stands at a machine's points stands across a stop.** The heavy attestations, the
    // pledges, the beacons, the frames and the proposals with their rolls of a window are the
    // certificate a device behind walks, and the set keeps them at their points for
    // `retained_windows` after the window closes (Canon, "The points a round stands at"). Points
    // that lived in memory alone went with the process: every holder of a window restarting inside
    // the retention took the window's certificate out of the network. So every cell a point takes is
    // appended to the file of that point, under the window it belongs to, and read back whole at the
    // next start; a cell torn by a loss of power is cut from its file at that start, before the next
    // cell lands behind it, so every cell is read where it was written. Nothing of a cell is a
    // secret: what stands at a point is public.
    fn points_at(&self, window: u64) -> PathBuf {
        self.root.join("points").join(format!("{window:020}"))
    }

    pub fn append_cell(
        &self,
        window: u64,
        point: &[u8; 16],
        cell: &[u8],
    ) -> Result<(), StoreError> {
        let directory = self.points_at(window);
        fs::create_dir_all(&directory).map_err(|e| said(&directory, e))?;
        let name: String = point.iter().map(|b| format!("{b:02x}")).collect();
        let at = directory.join(name);
        let mut file = fs::OpenOptions::new()
            .append(true)
            .create(true)
            .open(&at)
            .map_err(|e| said(&at, e))?;
        file.write_all(cell).map_err(|e| said(&at, e))
    }

    // Every cell standing at every point this store keeps, by window and point, in the order the
    // cells were taken. A file whose length is not a whole count of cells ends in a cell torn by a
    // loss of power, and is cut here to its last whole cell: this is read at the start, before
    // anything is appended, and a cell appended behind the tear would be read shifted by the length
    // of the tear, every cell after it with it.
    pub fn cells_standing(&self, cell_width: usize) -> Result<CellsStanding, StoreError> {
        let root = self.root.join("points");
        let mut out = Vec::new();
        let Ok(windows) = fs::read_dir(&root) else {
            return Ok(out);
        };
        for window in windows {
            let window = window.map_err(|e| said(&root, e))?.path();
            let Some(number) = window
                .file_name()
                .and_then(|n| n.to_str())
                .and_then(|n| n.parse::<u64>().ok())
            else {
                continue;
            };
            for file in fs::read_dir(&window).map_err(|e| said(&window, e))? {
                let at = file.map_err(|e| said(&window, e))?.path();
                let Some(name) = at.file_name().and_then(|n| n.to_str()) else {
                    continue;
                };
                let mut point = [0u8; 16];
                if name.len() != 32
                    || (0..16).any(|i| {
                        u8::from_str_radix(&name[2 * i..2 * i + 2], 16)
                            .map(|b| {
                                point[i] = b;
                                false
                            })
                            .unwrap_or(true)
                    })
                {
                    continue;
                }
                let bytes = fs::read(&at).map_err(|e| said(&at, e))?;
                let width = cell_width.max(1);
                let whole = bytes.len() - bytes.len() % width;
                if whole != bytes.len() {
                    let cut = u64::try_from(whole).map_err(|_| StoreError::WrongLength {
                        at: at.display().to_string(),
                        expected: whole,
                        found: bytes.len(),
                    })?;
                    let file = fs::OpenOptions::new()
                        .write(true)
                        .open(&at)
                        .map_err(|e| said(&at, e))?;
                    file.set_len(cut).map_err(|e| said(&at, e))?;
                    file.sync_all().map_err(|e| said(&at, e))?;
                }
                let cells: Vec<Vec<u8>> = bytes[..whole]
                    .chunks_exact(width)
                    .map(|cell| cell.to_vec())
                    .collect();
                out.push((number, point, cells));
            }
        }
        out.sort_by_key(|(window, point, _)| (*window, *point));
        Ok(out)
    }

    // The points of every window below `window` go, as they go from memory when the retention ends.
    pub fn drop_points_before(&self, window: u64) -> Result<(), StoreError> {
        let root = self.root.join("points");
        let Ok(windows) = fs::read_dir(&root) else {
            return Ok(());
        };
        for held in windows {
            let at = held.map_err(|e| said(&root, e))?.path();
            let Some(number) = at
                .file_name()
                .and_then(|n| n.to_str())
                .and_then(|n| n.parse::<u64>().ok())
            else {
                continue;
            };
            if number < window {
                fs::remove_dir_all(&at).map_err(|e| said(&at, e))?;
            }
        }
        Ok(())
    }

    pub fn put_proposal(&self, window: u64, bytes: &[u8]) -> Result<(), StoreError> {
        write_whole(&self.proposal_at(window), bytes)
    }

    pub fn proposal(&self, window: u64) -> Result<Option<Vec<u8>>, StoreError> {
        read_whole(&self.proposal_at(window))
    }

    // The head moves only onto a window this store can show. The check stands here rather than in
    // the caller because a caller that forgot it would leave a machine claiming a window it cannot
    // produce, and nothing downstream would say so until somebody asked for that proposal.
    pub fn set_head(&self, window: u64) -> Result<(), StoreError> {
        if self.proposal(window)?.is_none() {
            return Err(StoreError::HeadWithoutItsProposal { window });
        }
        write_whole(&self.head_at(), &window.to_le_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // A directory of this run, named by the test that asks for it: the tests share a parent and
    // none of them reads what another wrote.
    struct Scratch(PathBuf);

    impl Scratch {
        fn named(what: &str) -> Self {
            let unique = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("a test timestamp")
                .as_nanos();
            let at = std::env::temp_dir()
                .join(format!("mt-store-{what}-{}-{unique}", std::process::id()));
            fs::create_dir(&at).expect("a fresh scratch directory is writable");
            Self(at)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    // Scratch artifacts are retained for inspection; tests never remove existing files.

    // Two writers of one opening with two names, racing the exclusive write itself: exactly one
    // lands, the other learns so, the bytes that stand are the winner's, and nothing of either
    // opening is left beside them. A store is held by one process, so the race is run on the door
    // the opening goes through and not on two stores of one root. The wrong implementation
    // refused: read-then-rename, under which both would land and the last would stand.
    #[test]
    fn two_openings_of_one_record_leave_one_standing() {
        let scratch = Scratch::named("agreement-opening-race");
        // The root is bound to its network once, and the store that bound it is dropped: the race
        // is on the door of the opening, not on two stores of one root.
        drop(Store::open(scratch.path()).unwrap());
        let at = scratch.path().join("agreement-00000000000000000012");
        let barrier = std::sync::Barrier::new(2);
        let results = std::thread::scope(|scope| {
            let race = |byte: u8| {
                let at = &at;
                let barrier = &barrier;
                scope.spawn(move || {
                    barrier.wait();
                    let own = vec![byte; 90];
                    (own.clone(), publish_once(at, &own).unwrap())
                })
            };
            let a = race(0x51);
            let b = race(0x52);
            [a.join().unwrap(), b.join().unwrap()]
        });
        let standing = fs::read(&at).unwrap();
        assert_eq!(results.iter().filter(|(_, landed)| *landed).count(), 1);
        let winner = results.iter().find(|(_, landed)| *landed).unwrap();
        assert_eq!(
            winner.0, standing,
            "the bytes that stand are not the winner's"
        );
        let leftovers: Vec<_> = fs::read_dir(scratch.path())
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().to_string())
            .filter(|name| name.contains("opening-"))
            .collect();
        assert!(leftovers.is_empty(), "temporaries left: {leftovers:?}");
        // The store's door answers a later opening with what stands.
        let store = Store::open(scratch.path()).unwrap();
        assert_eq!(store.open_agreement(12, &[0x53; 90]).unwrap(), standing);
    }

    // One store, one process: a root held by a living store is refused to a second opening and
    // opens again once the first is dropped. The wrong implementation refused: a lock taken in
    // `open` and released when `open` returns, under which the second opening succeeds.
    #[test]
    fn a_store_is_held_by_one_opening_at_a_time() {
        let scratch = Scratch::named("one-store-one-process");
        let first = Store::open(scratch.path()).unwrap();
        assert_eq!(
            Store::open(scratch.path()).err(),
            Some(StoreError::HeldByAnother {
                at: scratch.path().display().to_string()
            })
        );
        first.put_closed(3).unwrap();
        drop(first);
        let second = Store::open(scratch.path()).unwrap();
        assert_eq!(second.closed().unwrap(), Some(3));
    }

    // A temporary of an opening left by a dead process, under the very name the next process draws,
    // is swept when the store opens, and the record opens. The wrong implementation refused: one that
    // left it standing, under which the next process -- process one of a container, serial nought --
    // meets AlreadyExists at its own temporary and is refused the record of the window for ever.
    #[test]
    fn a_dead_openings_temporary_is_swept_when_the_store_opens() {
        let scratch = Scratch::named("dead-opening");
        drop(Store::open(scratch.path()).unwrap());
        // The name this process draws for its next opening: its own id and the serial it stands at.
        let planted = scratch.path().join(format!(
            "agreement-00000000000000000012.opening-{}-0",
            std::process::id()
        ));
        fs::write(&planted, [0x33; 90]).unwrap();
        // And one of another process, dead too.
        let foreign = scratch
            .path()
            .join("agreement-00000000000000000013.opening-1-0");
        fs::write(&foreign, [0x34; 90]).unwrap();
        let store = Store::open(scratch.path()).unwrap();
        assert!(!planted.exists(), "a dead process's temporary stands");
        assert!(!foreign.exists(), "a dead process's temporary stands");
        let mut own = vec![0x51; 90];
        // Whatever serial this process stands at, the record opens.
        for _ in 0..3 {
            own[0] ^= 1;
            drop(store.open_agreement(12, &own).unwrap());
            store.drop_agreement(12).unwrap();
        }
        assert_eq!(store.open_agreement(12, &own).unwrap(), own);
    }

    // The cells of a point are read back in the order they were taken, by window and point, after a
    // reopening; a torn tail is not read; the windows below the retention go from the disk
    // as they go from memory. The wrong implementation refused: points kept in memory alone, under
    // which a reopened store stands at no point.
    #[test]
    fn the_cells_of_a_point_stand_across_a_reopening_and_go_with_the_retention() {
        let scratch = Scratch::named("points-kept");
        let point = [0x5Au8; 16];
        let other = [0x5Bu8; 16];
        {
            let store = Store::open(scratch.path()).unwrap();
            store.append_cell(12, &point, &[0x01; 8]).unwrap();
            store.append_cell(12, &point, &[0x02; 8]).unwrap();
            store.append_cell(12, &other, &[0x03; 8]).unwrap();
            store.append_cell(9, &point, &[0x04; 8]).unwrap();
            // A torn tail: three bytes of a cell that never finished.
            store.append_cell(12, &other, &[0x05; 3]).unwrap();
        }
        let store = Store::open(scratch.path()).unwrap();
        let standing = store.cells_standing(8).unwrap();
        assert_eq!(
            standing,
            vec![
                (9, point, vec![vec![0x04; 8]]),
                (12, point, vec![vec![0x01; 8], vec![0x02; 8]]),
                (12, other, vec![vec![0x03; 8]]),
            ]
        );
        store.drop_points_before(12).unwrap();
        let standing = store.cells_standing(8).unwrap();
        assert_eq!(standing.len(), 2);
        assert!(standing.iter().all(|(window, _, _)| *window == 12));
        store.drop_points_before(13).unwrap();
        assert!(store.cells_standing(8).unwrap().is_empty());
    }

    // A cell torn by a loss of power is cut at the next start, and the cell taken after the start is
    // read back where it was written, after every whole cell before the tear. The wrong
    // implementation refused: one appending behind the torn bytes, under which the cell taken after
    // the tear reads shifted by the length of the tear.
    #[test]
    fn a_cell_taken_after_a_tear_reads_where_it_was_written() {
        let scratch = Scratch::named("points-torn");
        let point = [0x5Cu8; 16];
        {
            let store = Store::open(scratch.path()).unwrap();
            store
                .append_cell(12, &point, &[1, 2, 3, 4, 5, 6, 7, 8])
                .unwrap();
            // Three bytes of a cell that never finished.
            store.append_cell(12, &point, &[0xEE, 0xEF, 0xF0]).unwrap();
        }
        {
            let store = Store::open(scratch.path()).unwrap();
            assert_eq!(
                store.cells_standing(8).unwrap(),
                vec![(12, point, vec![vec![1, 2, 3, 4, 5, 6, 7, 8]])]
            );
            store
                .append_cell(12, &point, &[9, 10, 11, 12, 13, 14, 15, 16])
                .unwrap();
        }
        let store = Store::open(scratch.path()).unwrap();
        assert_eq!(
            store.cells_standing(8).unwrap(),
            vec![(
                12,
                point,
                vec![
                    vec![1, 2, 3, 4, 5, 6, 7, 8],
                    vec![9, 10, 11, 12, 13, 14, 15, 16]
                ]
            )]
        );
    }

    // The last window closed is one number that moves forward and never back, and survives a
    // reopening. The wrong implementation refused: one keeping a history, or one letting the number
    // fall back to a window closed earlier.
    #[test]
    fn the_last_window_closed_is_one_number_that_only_moves_forward() {
        let scratch = Scratch::named("closed-window");
        {
            let store = Store::open(scratch.path()).unwrap();
            assert_eq!(store.closed().unwrap(), None);
            store.put_closed(12).unwrap();
            assert_eq!(store.closed().unwrap(), Some(12));
            store.put_closed(14).unwrap();
            store.put_closed(13).unwrap();
            assert_eq!(store.closed().unwrap(), Some(14));
        }
        let restarted = Store::open(scratch.path()).unwrap();
        assert_eq!(restarted.closed().unwrap(), Some(14));
        fs::write(scratch.path().join("closed"), [0u8; 7]).unwrap();
        assert!(matches!(
            restarted.closed(),
            Err(StoreError::WrongLength { .. })
        ));
    }

    // The record of an open window is read back whole after a reopening, written over by the next
    // writing, and gone once the window closes; a window never recorded answers with nothing. The
    // wrong implementations refused: one that kept the record after the close (a history, which
    // the set refuses), and one that refused a second writing of one window.
    #[test]
    fn an_agreement_record_survives_reopening_and_goes_with_its_window() {
        let scratch = Scratch::named("agreement-record");
        let first = vec![0x31; 90];
        let later = vec![0x32; 180];
        {
            let store = Store::open(scratch.path()).unwrap();
            assert_eq!(store.agreement(12).unwrap(), None);
            assert_eq!(store.open_agreement(12, &first).unwrap(), first);
            assert_eq!(store.agreement(12).unwrap(), Some(first.clone()));
        }
        let restarted = Store::open(scratch.path()).unwrap();
        assert_eq!(restarted.agreement(12).unwrap(), Some(first));
        restarted.put_agreement(12, &later).unwrap();
        assert_eq!(restarted.agreement(12).unwrap(), Some(later));
        assert_eq!(restarted.agreement(13).unwrap(), None);
        restarted.drop_agreement(12).unwrap();
        assert_eq!(restarted.agreement(12).unwrap(), None);
        assert!(!scratch
            .path()
            .join("agreement-00000000000000000012")
            .exists());
        // Dropping what is not there is not an error: the window closed once.
        restarted.drop_agreement(12).unwrap();
    }

    #[test]
    fn an_unbound_old_directory_is_not_automatically_a_new_network() {
        let scratch = Scratch::named("unbound-old-network");
        let old = [0x55; SECRET_BYTES];
        fs::write(scratch.path().join("identity"), old).unwrap();
        assert_eq!(
            Store::open(scratch.path()).err(),
            Some(StoreError::UnboundNetwork)
        );
        assert_eq!(fs::read(scratch.path().join("identity")).unwrap(), old);
        assert!(!scratch.path().join("genesis").exists());
    }

    #[test]
    fn a_persisted_directory_is_bound_to_its_exact_genesis() {
        let scratch = Scratch::named("another-network");
        Store::open(scratch.path()).unwrap();
        let expected = mt_state::tables::genesis_state_hash().unwrap();
        assert_eq!(fs::read(scratch.path().join("genesis")).unwrap(), expected);
        let mut found = expected;
        found[0] ^= 1;
        fs::write(scratch.path().join("genesis"), found).unwrap();
        assert_eq!(
            Store::open(scratch.path()).err(),
            Some(StoreError::WrongNetwork { expected, found })
        );
    }

    // Two drawings of one secret racing the exclusive write itself: one stands and the other is
    // refused as a secret that stands. A store is held by one process, so the race is run on the
    // door the drawing goes through and not on two stores of one root.
    #[test]
    fn concurrent_secret_creation_has_exactly_one_winner() {
        let scratch = Scratch::named("secret-race");
        drop(Store::open(scratch.path()).unwrap());
        let at = scratch.path().join("identity");
        let barrier = std::sync::Barrier::new(2);
        let results = std::thread::scope(|scope| {
            let a = scope.spawn(|| {
                barrier.wait();
                write_complete(&at, &[0x11; SECRET_BYTES], true)
            });
            let b = scope.spawn(|| {
                barrier.wait();
                write_complete(&at, &[0x22; SECRET_BYTES], true)
            });
            [a.join().unwrap(), b.join().unwrap()]
        });
        assert_eq!(results.iter().filter(|r| r.is_ok()).count(), 1);
        assert_eq!(
            results
                .iter()
                .filter(|r| **r == Err(StoreError::SecretStands))
                .count(),
            1
        );
        let standing = fs::read(&at).unwrap();
        assert!(standing == [0x11; SECRET_BYTES] || standing == [0x22; SECRET_BYTES]);
        let store = Store::open(scratch.path()).unwrap();
        assert_eq!(store.secret().unwrap().map(|s| s.to_vec()), Some(standing));
    }

    #[test]
    fn a_stale_temporary_symlink_is_never_followed() {
        #[cfg(unix)]
        {
            let scratch = Scratch::named("temporary-symlink");
            let victim = scratch.path().join("untouched");
            fs::write(&victim, b"keep").unwrap();
            let stale = scratch.path().join("value.writing");
            std::os::unix::fs::symlink(&victim, &stale).unwrap();
            write_whole(&scratch.path().join("value"), b"new").unwrap();
            assert_eq!(fs::read(&victim).unwrap(), b"keep");
            assert_eq!(fs::read(scratch.path().join("value")).unwrap(), b"new");
            assert!(create_closed(&stale).is_err());
        }
    }

    #[test]
    fn a_machine_draws_its_secret_once_and_a_second_drawing_is_refused() {
        let scratch = Scratch::named("one-secret");
        let store = Store::open(scratch.path()).expect("a store opens");
        assert!(store.secret().expect("a store answers").is_none());
        store
            .bear_secret(&[0x11u8; SECRET_BYTES])
            .expect("the first drawing stands");
        assert_eq!(
            store.secret().expect("a store answers").map(|s| *s),
            Some([0x11u8; SECRET_BYTES])
        );
        // The second is refused rather than overwriting: what stood is what a machine is known by.
        assert_eq!(
            store.bear_secret(&[0x22u8; SECRET_BYTES]),
            Err(StoreError::SecretStands)
        );
        assert_eq!(
            store.secret().expect("a store answers").map(|s| *s),
            Some([0x11u8; SECRET_BYTES]),
            "the refused drawing moved the secret that stood"
        );
    }

    #[test]
    fn a_secret_is_closed_to_everyone_but_its_owner() {
        let scratch = Scratch::named("secret-mode");
        let store = Store::open(scratch.path()).expect("a store opens");
        store
            .bear_secret(&[0x33u8; SECRET_BYTES])
            .expect("it is drawn");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(store.secret_at())
                .expect("the file stands")
                .permissions()
                .mode();
            assert_eq!(
                mode & 0o777,
                SECRET_MODE,
                "the secret is readable by others"
            );
        }
    }

    // The named wrong implementation: a file created at whatever the umask grants and closed after
    // the bytes are in it. Between those two moments the secret of a machine stands readable to
    // everyone on that machine, so what is asserted here is the mode of the **temporary**, which is
    // where the bytes actually land.
    #[test]
    #[cfg(unix)]
    fn a_file_is_closed_to_others_at_the_moment_it_is_created() {
        use std::os::unix::fs::PermissionsExt;
        let scratch = Scratch::named("closed-at-creation");
        let at = scratch.path().join("value");
        let temporary = at.with_extension("writing");
        {
            let file = create_closed(&temporary).expect("a file opens");
            drop(file);
        }
        let mode = fs::metadata(&temporary)
            .expect("the temporary stands")
            .permissions()
            .mode();
        assert_eq!(
            mode & 0o777,
            SECRET_MODE,
            "the temporary is readable by others"
        );
        // A stale file is refused rather than reopened or truncated.
        fs::set_permissions(&temporary, fs::Permissions::from_mode(0o644)).expect("widened");
        assert!(create_closed(&temporary).is_err());
        assert_eq!(
            fs::metadata(&temporary).unwrap().permissions().mode() & 0o777,
            0o644
        );
    }

    #[test]
    fn a_proposal_is_read_back_byte_for_byte_and_an_absent_one_is_nothing() {
        let scratch = Scratch::named("proposals");
        let store = Store::open(scratch.path()).expect("a store opens");
        assert_eq!(store.proposal(7).expect("a store answers"), None);
        let bytes: Vec<u8> = (0..1000u32).map(|i| i as u8).collect();
        store.put_proposal(7, &bytes).expect("it is stored");
        assert_eq!(store.proposal(7).expect("a store answers"), Some(bytes));
        assert_eq!(store.proposal(8).expect("a store answers"), None);
    }

    #[test]
    fn the_head_moves_only_onto_a_window_this_store_can_show() {
        let scratch = Scratch::named("head-follows");
        let store = Store::open(scratch.path()).expect("a store opens");
        assert_eq!(store.head().expect("a store answers"), None);
        // The named wrong implementation: a head that moves first and a proposal that follows. A
        // machine crashing between the two would claim a window it cannot produce.
        assert_eq!(
            store.set_head(3),
            Err(StoreError::HeadWithoutItsProposal { window: 3 })
        );
        assert_eq!(store.head().expect("a store answers"), None);
        store
            .put_proposal(3, b"the bytes of a proposal")
            .expect("stored");
        store.set_head(3).expect("the head follows what it names");
        assert_eq!(store.head().expect("a store answers"), Some(3));
    }

    #[test]
    fn a_store_whose_head_lost_its_proposal_refuses_to_open() {
        let scratch = Scratch::named("head-orphaned");
        let store = Store::open(scratch.path()).expect("a store opens");
        // Construct a crashed/orphaned directory directly, without deleting a proposal, once the
        // store that bound the root is dropped: one store, one process.
        let head_at = store.head_at();
        drop(store);
        fs::write(head_at, 5u64.to_le_bytes()).expect("an orphaned head fixture");
        assert_eq!(
            Store::open(scratch.path()).err(),
            Some(StoreError::HeadWithoutItsProposal { window: 5 })
        );
    }

    #[test]
    fn a_value_of_the_wrong_width_is_refused_before_it_is_read() {
        let scratch = Scratch::named("wrong-width");
        let store = Store::open(scratch.path()).expect("a store opens");
        fs::write(store.secret_at(), [0u8; SECRET_BYTES - 1]).expect("written");
        assert!(matches!(
            store.secret(),
            Err(StoreError::WrongLength { expected, found, .. })
                if expected == SECRET_BYTES && found == SECRET_BYTES - 1
        ));
        fs::write(store.head_at(), [0u8; HEAD_BYTES + 1]).expect("written");
        assert!(matches!(
            store.head(),
            Err(StoreError::WrongLength { expected, .. }) if expected == HEAD_BYTES
        ));
    }

    #[test]
    fn a_write_leaves_no_half_value_behind_it() {
        let scratch = Scratch::named("whole-writes");
        let store = Store::open(scratch.path()).expect("a store opens");
        store.put_proposal(1, b"the first").expect("stored");
        store
            .put_proposal(1, b"the second, which is longer")
            .expect("stored");
        assert_eq!(
            store.proposal(1).expect("a store answers"),
            Some(b"the second, which is longer".to_vec())
        );
        // Nothing of the writing stands beside the value: a temporary left behind would be read by
        // a listing of the directory as a proposal of a window nobody named.
        let held: Vec<String> = fs::read_dir(scratch.path().join("proposals"))
            .expect("the directory is readable")
            .map(|e| {
                e.expect("an entry")
                    .file_name()
                    .to_string_lossy()
                    .to_string()
            })
            .collect();
        assert_eq!(held, vec![format!("{:020}", 1)]);
    }

    #[test]
    fn what_a_person_holds_survives_a_stop_and_is_closed_to_others() {
        let scratch = Scratch::named("notes");
        let store = Store::open(scratch.path()).expect("a store opens");
        assert!(store.notes().expect("a store answers").is_empty());
        let held: Vec<u8> = (0..500u32).map(|i| i as u8).collect();
        store.put_notes(&held).expect("stored");
        assert_eq!(*store.notes().expect("a store answers"), held);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(store.notes_at())
                .expect("the file stands")
                .permissions()
                .mode();
            assert_eq!(
                mode & 0o777,
                SECRET_MODE,
                "what a person holds is readable by others"
            );
        }
        // And a second start reaches what the first wrote.
        drop(store);
        let again = Store::open(scratch.path()).expect("a store opens again");
        assert_eq!(*again.notes().expect("a store answers"), held);
    }

    #[test]
    fn a_store_reopened_holds_what_it_held() {
        let scratch = Scratch::named("reopened");
        {
            let store = Store::open(scratch.path()).expect("a store opens");
            store.bear_secret(&[0x44u8; SECRET_BYTES]).expect("drawn");
            store
                .put_proposal(9, b"a proposal of the ninth")
                .expect("stored");
            store.set_head(9).expect("the head follows");
        }
        let store = Store::open(scratch.path()).expect("a store opens again");
        assert_eq!(
            store.secret().expect("a store answers").map(|s| *s),
            Some([0x44u8; SECRET_BYTES])
        );
        assert_eq!(store.head().expect("a store answers"), Some(9));
        assert_eq!(
            store.proposal(9).expect("a store answers"),
            Some(b"a proposal of the ninth".to_vec())
        );
    }
}
