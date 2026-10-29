//! What a running node last did with a window, read by its operator's `status` (issue #21; the
//! Author's decision on the codes of the earlier core, (a), record 358 of the constitution chain,
//! 2026-10-29 12:48 UTC): the three verdicts and codes of `core/Montana-Core` -- `no quorum` 1,
//! `no data` 2, `no diagnostics` 4 (Consensus, "The way back", "The liveness price") -- with the
//! confirmations refused on that window beside every reading as `refused N`.
//!
//! The reading is an operator signal and not a value of the protocol: it enters no envelope, no
//! root, no message of the wire and no rule of acceptance, and nothing of the chain reads it. It is
//! one line in one file of the data directory, put in place whole by a rename. A run starts with
//! none of its own, so a reading of an earlier run never stands for this one, and `status` reads
//! the absence of a reading as `no diagnostics`.

use std::path::{Path, PathBuf};

use crate::identity::NodeError;

/// The file of the reading, in the data directory.
pub const READING_FILE: &str = "reading";
const WRITING_FILE: &str = "reading.writing";

/// What a window stood short of: each verdict reads `no` and its name, with the exit code of
/// `status`. Code 3 is given to none: a refused proof is a count beside the verdict and never the
/// verdict (Consensus, "The way back").
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lack {
    Quorum,
    Data,
    Diagnostics,
}

impl Lack {
    pub const ALL: [Lack; 3] = [Lack::Quorum, Lack::Data, Lack::Diagnostics];

    pub fn exit_code(self) -> u8 {
        match self {
            Self::Quorum => 1,
            Self::Data => 2,
            Self::Diagnostics => 4,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Quorum => "no quorum",
            Self::Data => "no data",
            Self::Diagnostics => "no diagnostics",
        }
    }
}

/// What the node last did with a window: closed it, or stood short of it on a verdict. A reading
/// closes nothing and moves no head.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reading {
    Closed { window: u64, refused: u64 },
    Stalled { on: Lack, window: u64, refused: u64 },
}

impl Reading {
    pub fn exit_code(&self) -> u8 {
        match *self {
            Self::Closed { .. } => 0,
            Self::Stalled { on, .. } => on.exit_code(),
        }
    }

    /// The reading back from the line `Display` writes, and nothing else.
    pub fn parse(line: &str) -> Option<Self> {
        let (head, refused) = line.rsplit_once("; refused ")?;
        let refused = refused.parse().ok()?;
        if let Some(window) = head.strip_prefix("closed window ") {
            return Some(Self::Closed {
                window: window.parse().ok()?,
                refused,
            });
        }
        let (name, window) = head.split_once("; window ")?;
        let on = Lack::ALL.into_iter().find(|on| on.name() == name)?;
        Some(Self::Stalled {
            on,
            window: window.parse().ok()?,
            refused,
        })
    }
}

impl std::fmt::Display for Reading {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Closed { window, refused } => {
                write!(f, "closed window {window}; refused {refused}")
            },
            Self::Stalled {
                on,
                window,
                refused,
            } => write!(f, "{}; window {window}; refused {refused}", on.name()),
        }
    }
}

pub fn path(data_dir: &Path) -> PathBuf {
    data_dir.join(READING_FILE)
}

/// Puts the reading in place whole. A reading that cannot be written is an error of the node, as
/// any write of its data directory is, so a stale reading never outlives a failed one.
pub fn write(data_dir: &Path, reading: Reading) -> Result<(), NodeError> {
    let writing = data_dir.join(WRITING_FILE);
    std::fs::write(&writing, format!("{reading}\n"))?;
    std::fs::rename(&writing, path(data_dir))?;
    Ok(())
}

/// Removes the reading of an earlier run: until this run reads something, `status` reads none.
pub fn clear(data_dir: &Path) -> Result<(), NodeError> {
    match std::fs::remove_file(path(data_dir)) {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e.into()),
        _ => Ok(()),
    }
}

/// The reading that stands, where a whole one does.
pub fn read(data_dir: &Path) -> Option<Reading> {
    let line = std::fs::read_to_string(path(data_dir)).ok()?;
    Reading::parse(line.trim_end())
}

#[cfg(test)]
mod tests {
    use super::*;

    // Refuses a reading that does not come back as written, a code given to two verdicts or to the
    // retired 3, a closed window that does not read 0, and a cleared store that keeps a reading.
    #[test]
    fn a_reading_comes_back_as_written_with_its_code() {
        let dir = std::env::temp_dir().join(format!("montana-node-reading-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        assert_eq!(read(&dir), None);
        let closed = Reading::Closed {
            window: 7,
            refused: 2,
        };
        write(&dir, closed).unwrap();
        assert_eq!(read(&dir), Some(closed));
        assert_eq!(closed.to_string(), "closed window 7; refused 2");
        assert_eq!(closed.exit_code(), 0);
        for (on, code, line) in [
            (Lack::Quorum, 1, "no quorum; window 8; refused 3"),
            (Lack::Data, 2, "no data; window 8; refused 3"),
            (Lack::Diagnostics, 4, "no diagnostics; window 8; refused 3"),
        ] {
            let stalled = Reading::Stalled {
                on,
                window: 8,
                refused: 3,
            };
            write(&dir, stalled).unwrap();
            assert_eq!(read(&dir), Some(stalled));
            assert_eq!(stalled.to_string(), line);
            assert_eq!(stalled.exit_code(), code);
        }
        assert_eq!(Reading::parse("proof refused; window 8; refused 3"), None);
        clear(&dir).unwrap();
        assert_eq!(read(&dir), None);
        clear(&dir).unwrap();
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 0);
        std::fs::remove_dir(&dir).unwrap();
    }
}
