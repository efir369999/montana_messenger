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
use std::io::Write;
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
    // A file of a width its value does not have. Refused before it is read, like every object of
    // this protocol.
    WrongLength {
        at: String,
        expected: usize,
        found: usize,
    },
    // A machine that already drew its secret, asked to draw a second.
    SecretStands,
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
    let directory = at.parent().unwrap_or(Path::new("."));
    let beside = at.with_extension("writing");
    {
        let mut file = create_closed(&beside)?;
        file.write_all(bytes).map_err(|e| said(&beside, e))?;
        file.sync_all().map_err(|e| said(&beside, e))?;
    }
    fs::rename(&beside, at).map_err(|e| said(at, e))?;
    // The rename itself is what a crash may lose, so the directory holding it is flushed too: on
    // the systems this runs on a renamed entry is not durable until its directory is.
    if let Ok(handle) = fs::File::open(directory) {
        let _ = handle.sync_all();
    }
    Ok(())
}

// A file opened for writing and closed to everyone but its owner at the moment it is created. On a
// system holding the permissions of a Unix file the mode is given to the open itself, and given
// again to the path, so a temporary left behind by an earlier run cannot carry wider permissions
// into this one.
#[cfg(unix)]
fn create_closed(at: &Path) -> Result<fs::File, StoreError> {
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    let file = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(SECRET_MODE)
        .open(at)
        .map_err(|e| said(at, e))?;
    fs::set_permissions(at, fs::Permissions::from_mode(SECRET_MODE)).map_err(|e| said(at, e))?;
    Ok(file)
}

// A system without the permissions of a Unix file leaves the file at whatever it grants by
// default, and this crate says so rather than implying a protection it did not apply.
#[cfg(not(unix))]
fn create_closed(at: &Path) -> Result<fs::File, StoreError> {
    fs::File::create(at).map_err(|e| said(at, e))
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

pub struct Store {
    root: PathBuf,
}

impl Store {
    // Opening makes the tree of directories if it is not there and answers with a store whose
    // head, if it names a window, has that window's proposal beside it.
    pub fn open(root: impl AsRef<Path>) -> Result<Self, StoreError> {
        let root = root.as_ref().to_path_buf();
        let proposals = root.join("proposals");
        fs::create_dir_all(&proposals).map_err(|e| said(&proposals, e))?;
        let store = Self { root };
        if let Some(window) = store.head()? {
            if store.proposal(window)?.is_none() {
                return Err(StoreError::HeadWithoutItsProposal { window });
            }
        }
        Ok(store)
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
        if self.secret_at().exists() {
            return Err(StoreError::SecretStands);
        }
        let at = self.secret_at();
        write_whole(&at, secret)?;
        self.close_the_file_to_others(&at)
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
            let at = std::env::temp_dir().join(format!("mt-store-{what}"));
            let _ = fs::remove_dir_all(&at);
            fs::create_dir_all(&at).expect("a scratch directory is writable");
            Self(at)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
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
        // And a temporary left behind by an earlier run with wider permissions is closed rather
        // than inherited.
        fs::set_permissions(&temporary, fs::Permissions::from_mode(0o644)).expect("widened");
        let file = create_closed(&temporary).expect("a file opens");
        drop(file);
        let mode = fs::metadata(&temporary)
            .expect("the temporary stands")
            .permissions()
            .mode();
        assert_eq!(
            mode & 0o777,
            SECRET_MODE,
            "a stale temporary carried its permissions"
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
        {
            let store = Store::open(scratch.path()).expect("a store opens");
            store.put_proposal(5, b"a proposal").expect("stored");
            store.set_head(5).expect("the head follows");
        }
        // Something other than this crate took the proposal away. Opening says so rather than
        // starting a machine that claims a window it cannot show.
        fs::remove_file(scratch.path().join("proposals").join(format!("{:020}", 5)))
            .expect("the file is removable");
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
