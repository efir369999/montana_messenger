//! WHAT THIS COMPUTER HOLDS, MEASURED ON ITS DISK (iOS MTDiskUse, Data and Storage «ON THIS PHONE»; the author's word 18.10.2026
//! 10:2x MSK: «Montana weighs 20 GB, I cannot see what weighs so much nor how to clean it»): the person's folder walked once, each
//! file counted once, every byte in one row -- the attachments of the letters, the files no letter names, the walls' pictures, the
//! copies waiting on their way (this program's own files in the temporary folder), the parts kept for others, the files opened from
//! the letters (only those this program wrote out), the history (the vault and the archive), the faces, and the rest.

use serde::Serialize;
use std::collections::HashSet;
use std::path::{Path, PathBuf};

#[derive(Serialize, Default, Debug, Clone, PartialEq)]
pub struct Use {
    pub chats: u64,
    pub unnamed: u64,
    pub walls: u64,
    pub shelf: u64,
    pub kept: u64,
    pub opened: u64,
    pub history: u64,
    pub faces: u64,
    pub other: u64,
    pub total: u64,
}

/// A file's bytes, or a folder's, every file inside counted once.
pub fn size(p: &Path) -> u64 {
    let Ok(m) = std::fs::symlink_metadata(p) else { return 0 };
    if m.is_file() {
        return m.len();
    }
    if !m.is_dir() {
        return 0;
    }
    std::fs::read_dir(p).into_iter().flatten().flatten().map(|e| size(&e.path())).sum()
}

/// THE MEASURE: `base` the person's folder (the store in `media`, the faces in `faces`, the parts kept for others in `keeping`, the
/// vault and the archive), `letters` and `walls` the store's keys of the files a letter or a wall names, `opened` the files this
/// program wrote out for a viewer, `shelf` its own files on their way in the temporary folder.
pub fn measure(base: &Path, letters: &HashSet<String>, walls: &HashSet<String>, opened: &[PathBuf], shelf: &[PathBuf]) -> Use {
    let mut u = Use::default();
    for e in std::fs::read_dir(base.join("media")).into_iter().flatten().flatten() {
        let p = e.path();
        let name = p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
        let key = name.split('.').next().unwrap_or("");
        let n = size(&p);
        if letters.contains(key) {
            u.chats += n;
        } else if walls.contains(key) {
            u.walls += n;
        } else {
            u.unnamed += n;
        }
    }
    u.kept = size(&base.join("keeping"));
    u.faces = size(&base.join("faces"));
    u.history = size(&base.join("vault")) + size(&base.join("archive"));
    u.opened = opened.iter().map(|p| size(p)).sum();
    u.shelf = shelf.iter().map(|p| size(p)).sum();
    let inside = size(base);
    let named = u.chats + u.unnamed + u.walls + u.kept + u.faces + u.history;
    u.other = inside.saturating_sub(named);
    u.total = inside + u.opened + u.shelf;
    u
}

/// This program's own files on their way in the temporary folder -- a film being written (videoconv, post::squeeze), a voice being
/// encoded (voice): only names it makes itself, older than an hour, so nothing still at work and nobody else's file is named.
pub fn shelf_files() -> Vec<PathBuf> {
    const OWN: [&str; 2] = ["montana-film-", "montana-voice-"];
    let hour = std::time::Duration::from_secs(3600);
    std::fs::read_dir(std::env::temp_dir()).into_iter().flatten().flatten()
        .filter(|e| { let n = e.file_name().to_string_lossy().to_string(); OWN.iter().any(|p| n.starts_with(p)) })
        .filter(|e| e.metadata().and_then(|m| m.modified()).ok().and_then(|t| t.elapsed().ok()).is_some_and(|a| a > hour))
        .map(|e| e.path())
        .collect()
}

/// Clears what `measure` named as waiting: the bytes freed.
pub fn clear(paths: &[PathBuf]) -> u64 {
    paths.iter().map(|p| {
        let n = size(p);
        let gone = if p.is_dir() { std::fs::remove_dir_all(p).is_ok() } else { std::fs::remove_file(p).is_ok() };
        if gone { n } else { 0 }
    }).sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_byte_of_the_folder_stands_in_one_row() {
        let d = std::env::temp_dir().join(format!("montana-disk-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let put = |rel: &str, n: usize| {
            let p = d.join(rel);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(p, vec![7u8; n]).unwrap();
        };
        put("media/aaaa.sealed", 1000);   // a letter's
        put("media/bbbb.parts/p0000000.sealed", 700);   // a letter's big file
        put("media/bbbb.parts/whole.sealed", 8);
        put("media/cccc.sealed", 300);   // a wall's
        put("media/dddd.sealed", 50);   // nobody's
        put("keeping/x.keep", 40);
        put("faces/f.sealed", 20);
        put("vault/chats.sealed", 90);
        put("archive/blocks/1", 10);
        put("EBWebView/cache", 5000);
        put("settings.json", 2);
        let opened = d.join("opened.txt");
        std::fs::write(&opened, vec![1u8; 60]).unwrap();
        let letters: HashSet<String> = ["aaaa".to_string(), "bbbb".to_string()].into();
        let walls: HashSet<String> = ["cccc".to_string()].into();
        let u = measure(&d, &letters, &walls, std::slice::from_ref(&opened), &[]);
        assert_eq!((u.chats, u.walls, u.unnamed, u.kept, u.faces, u.history), (1708, 300, 50, 40, 20, 100));
        assert_eq!(u.opened, 60);
        // the opened file lies inside this test's folder; in the program it lies in the person's Downloads, outside it
        assert_eq!(u.other, 5000 + 2 + 60);
        assert_eq!(u.total, size(&d) + 60);
        assert_eq!(clear(std::slice::from_ref(&opened)), 60);
        assert!(!opened.exists());
        let _ = std::fs::remove_dir_all(&d);
    }
}
