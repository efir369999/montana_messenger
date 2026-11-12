// What an operator's default lines may say, and where the rest goes (#22, K1). A default line names
// an event and its window; it carries no address of this machine or of another, no part of a
// nullifier, no key and no amount. Those details go to one file in the data directory, opened for
// appending and closed to its owner, and only there: the formatter of a detail runs only once that
// file is named, so a line printed where none was (a test, a tool) never formats one.
//
// Two steps, because a refused start writes nothing (Consensus, "The cold start"): `keep_at` names
// the file and holds the details in memory, and `stand` creates it once every refusal of the start
// is behind. A start refused between the two leaves the data directory as it found it.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

enum Details {
    Held { at: PathBuf, lines: Vec<String> },
    Standing(File),
}

static DETAILS: OnceLock<Mutex<Details>> = OnceLock::new();

/// The name of the owner-only file of details, in the data directory.
pub const FILE: &str = "private.log";

/// Names the owner-only file of this process in the data directory, once, and holds the details
/// in memory until `stand`. Nothing is written here.
pub fn keep_at(data: &Path) {
    let _ = DETAILS.set(Mutex::new(Details::Held {
        at: data.join(FILE),
        lines: Vec::new(),
    }));
}

/// Creates the file of details, closed to its owner, and writes what was held. A file that stands
/// is appended to and narrowed to its owner, never widened. Before `keep_at` it does nothing.
pub fn stand() -> std::io::Result<()> {
    let Some(details) = DETAILS.get() else {
        return Ok(());
    };
    let Ok(mut details) = details.lock() else {
        return Ok(());
    };
    if let Details::Held { at, lines } = &*details {
        let mut file = OpenOptions::new()
            .append(true)
            .create(true)
            .mode(0o600)
            .open(at)?;
        file.set_permissions(std::fs::Permissions::from_mode(0o600))?;
        for line in lines {
            writeln!(file, "{line}")?;
        }
        *details = Details::Standing(file);
    }
    Ok(())
}

/// Prints the public line and keeps the detail, with its UTC second, for the owner-only file.
pub fn say(public: &str, detail: impl FnOnce() -> String) {
    println!("{public}");
    note(detail);
}

/// Keeps a detail for the owner-only file and prints nothing.
pub fn note(detail: impl FnOnce() -> String) {
    let Some(details) = DETAILS.get() else {
        return;
    };
    let second = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    if let Ok(mut details) = details.lock() {
        let line = format!("{second} {}", detail());
        match &mut *details {
            Details::Held { lines, .. } => lines.push(line),
            Details::Standing(file) => {
                let _ = writeln!(file, "{line}");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // One test, so the order of naming, noting and standing within this process is the order
    // written here.
    #[test]
    fn a_detail_is_formatted_only_into_a_file_closed_to_its_owner() {
        // Before the file is named, the formatter must not run: the public line is all there is.
        note(|| panic!("a detail was formatted with no owner-only file"));
        assert!(stand().is_ok());
        let data = std::env::temp_dir().join(format!("mt-private-{}", std::process::id()));
        std::fs::create_dir_all(data.as_path()).expect("a temporary directory");
        let at = data.join(FILE);
        // A file left wide by something else is narrowed when it stands, never kept wide.
        std::fs::write(at.as_path(), b"").expect("a wide file");
        std::fs::set_permissions(at.as_path(), std::fs::Permissions::from_mode(0o644))
            .expect("widened");
        keep_at(data.as_path());
        note(|| "held".to_string());
        // Held, not written: a start refused here leaves the file as it found it.
        assert!(std::fs::read(at.as_path())
            .expect("the file reads")
            .is_empty());
        stand().expect("the file of details stands");
        note(|| "a detail".to_string());
        let mode = std::fs::metadata(at.as_path())
            .expect("the file stands")
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
        let written = std::fs::read_to_string(at.as_path()).expect("the file reads");
        let lines: Vec<&str> = written.lines().collect();
        assert_eq!(lines.len(), 2, "{written}");
        assert!(lines[0].ends_with(" held"), "{written}");
        assert!(lines[1].ends_with(" a detail"), "{written}");
        let _ = std::fs::remove_dir_all(data.as_path());
    }
}
