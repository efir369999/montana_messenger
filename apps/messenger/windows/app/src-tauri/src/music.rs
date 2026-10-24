//! THE PERSON'S OWN MUSIC (iOS MTMusicFolders, «the lent folders», the author's word 24.09): folders of this computer the person
//! lends to the music page -- walked for their music files, which stand among the chats' tracks under «Папки». The folders are
//! kept in the person's vault (sealed: where a person keeps their music is theirs); a track's place is never said on the page --
//! its name alone, as iOS («take the addresses out of the tracks everywhere»).
//!
//! THE SHARE SHEET OF WINDOWS (iOS UIActivityViewController): a link or words handed to the system's own «Поделиться» for this
//! window (DataTransferManager), where the person chooses the program that takes them.
use serde::Serialize;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::vault::Vault;

const KEY: &str = "musicFolders";
/// The kinds of file the page plays (the chats' own list).
const AUDIO: [&str; 7] = ["mp3", "m4a", "aac", "wav", "ogg", "flac", "opus"];
/// A walk stops here: a folder lent is music, not a disk.
const MOST: usize = 5000;
const DEPTH: usize = 8;
/// A track handed to the window whole: the page plays a file, not a stream.
const LARGEST: u64 = 400 * 1024 * 1024;

#[derive(Serialize, Debug, Clone)]
pub struct Track {
    pub id: String,
    pub title: String,
    pub e: String,
    pub sz: u64,
    pub at: i64,
}

/// What the last walk found: a track's name to its place, asked by the play.
static FOUND: Mutex<Option<HashMap<String, PathBuf>>> = Mutex::new(None);

pub fn folders(v: &Vault) -> Vec<String> {
    v.get(KEY).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}
fn keep(v: &Vault, list: &[String]) -> bool {
    serde_json::to_vec(list).is_ok_and(|b| v.set(KEY, &b))
}
/// A folder lent: kept once.
pub fn add(v: &Vault, folder: &Path) -> bool {
    let s = folder.to_string_lossy().to_string();
    let mut list = folders(v);
    if !list.contains(&s) {
        list.push(s);
    }
    keep(v, &list)
}
/// The names of the folders, for the page's list of them (their last part: a folder's name, not its path).
pub fn names(v: &Vault) -> Vec<String> {
    folders(v).iter().map(|f| Path::new(f).file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_else(|| f.clone())).collect()
}

/// THE WALK (iOS MTMusicFolders.walk): every lent folder, its music files to the depth of eight, five thousand at most; a track
/// is named by its place's own hash, so the page never holds the path.
pub fn walk(v: &Vault) -> Vec<Track> {
    let mut found = HashMap::new();
    let mut out = Vec::new();
    fn go(dir: &Path, depth: usize, out: &mut Vec<Track>, found: &mut HashMap<String, PathBuf>) {
        if depth > DEPTH || out.len() >= MOST {
            return;
        }
        let Ok(rd) = std::fs::read_dir(dir) else { return };
        let mut entries: Vec<_> = rd.flatten().collect();
        entries.sort_by_key(|e| e.file_name());
        for e in entries {
            if out.len() >= MOST {
                return;
            }
            let p = e.path();
            let Ok(meta) = e.metadata() else { continue };
            if meta.is_dir() {
                go(&p, depth + 1, out, found);
                continue;
            }
            let ext = p.extension().map(|x| x.to_string_lossy().to_lowercase()).unwrap_or_default();
            if !AUDIO.contains(&ext.as_str()) {
                continue;
            }
            let id = format!("lent-{}", crate::wire::hex(&crate::wire::sha(&[b"mt-music-lent\0", p.to_string_lossy().as_bytes()])[..12]));
            let at = meta.modified().ok().and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok()).map_or(0, |d| d.as_millis() as i64);
            let title = p.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
            out.push(Track { id: id.clone(), title, e: ext, sz: meta.len(), at });
            found.insert(id, p);
        }
    }
    for f in folders(v) {
        go(Path::new(&f), 0, &mut out, &mut found);
    }
    *FOUND.lock().unwrap() = Some(found);
    out
}

/// Where a lent track lies, for its tags (trackmeta): only a track the last walk found.
pub fn path_of(id: &str) -> Option<PathBuf> {
    FOUND.lock().unwrap().as_ref()?.get(id).cloned()
}

/// A lent track's bytes for the play: only a track the last walk found, and only while its file stands.
pub fn bytes(id: &str) -> Option<Vec<u8>> {
    let p = FOUND.lock().unwrap().as_ref()?.get(id)?.clone();
    if std::fs::metadata(&p).ok()?.len() > LARGEST {
        return None;
    }
    std::fs::read(p).ok()
}

/// THE FOLDER PICKER OF WINDOWS (iOS the document picker for a folder): the system's own dialog over this window, a folder of the
/// file system alone; nothing when the person closes it.
#[cfg(windows)]
pub fn pick_folder(owner: isize) -> Option<PathBuf> {
    use windows::Win32::Foundation::HWND;
    use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CoTaskMemFree, CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED};
    use windows::Win32::UI::Shell::{FileOpenDialog, IFileOpenDialog, FOS_FORCEFILESYSTEM, FOS_PICKFOLDERS, SIGDN_FILESYSPATH};
    // SAFETY: COM is begun on this thread for the dialog's life; every interface is released by its drop; the path's memory is
    // the task allocator's and is freed once read
    unsafe {
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
        let d: IFileOpenDialog = CoCreateInstance(&FileOpenDialog, None, CLSCTX_INPROC_SERVER).ok()?;
        let o = d.GetOptions().ok()?;
        d.SetOptions(o | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM).ok()?;
        d.Show(Some(HWND(owner as *mut _))).ok()?;
        let item = d.GetResult().ok()?;
        let p = item.GetDisplayName(SIGDN_FILESYSPATH).ok()?;
        let s = p.to_string().ok();
        CoTaskMemFree(Some(p.0 as *const _));
        s.map(PathBuf::from)
    }
}
#[cfg(not(windows))]
pub fn pick_folder(_: isize) -> Option<PathBuf> {
    None
}

/// THE SHARE SHEET (iOS UIActivityViewController): the words -- and the link, when one is given -- handed to Windows' own
/// «Поделиться» for this window. Asked on the window's own thread.
#[cfg(windows)]
pub fn share(owner: isize, title: &str, text: &str, link: Option<&str>) -> bool {
    use windows::core::HSTRING;
    use windows::ApplicationModel::DataTransfer::{DataRequestedEventArgs, DataTransferManager};
    use windows::Foundation::{TypedEventHandler, Uri};
    use windows::Win32::Foundation::HWND;
    use windows::Win32::System::WinRT::RoGetActivationFactory;
    use windows::Win32::UI::Shell::IDataTransferManagerInterop;
    static TOKEN: Mutex<Option<i64>> = Mutex::new(None);
    let (title, text, link) = (title.to_string(), text.to_string(), link.map(str::to_string));
    // SAFETY: the interop factory and the manager are COM objects released by their drops; the window handle is this program's own
    let run = || -> windows::core::Result<()> {
        let interop: IDataTransferManagerInterop = unsafe { RoGetActivationFactory(&HSTRING::from("Windows.ApplicationModel.DataTransfer.DataTransferManager"))? };
        let hwnd = HWND(owner as *mut _);
        let manager: DataTransferManager = unsafe { interop.GetForWindow(hwnd)? };
        if let Some(t) = TOKEN.lock().unwrap().take() {
            let _ = manager.RemoveDataRequested(t);
        }
        let handler = TypedEventHandler::<DataTransferManager, DataRequestedEventArgs>::new(move |_, args| {
            if let Some(args) = args.as_ref() {
                let data = args.Request()?.Data()?;
                data.Properties()?.SetTitle(&HSTRING::from(title.as_str()))?;
                data.SetText(&HSTRING::from(text.as_str()))?;
                if let Some(l) = link.as_deref() {
                    if let Ok(uri) = Uri::CreateUri(&HSTRING::from(l)) {
                        data.SetWebLink(&uri)?;
                    }
                }
            }
            Ok(())
        });
        *TOKEN.lock().unwrap() = Some(manager.DataRequested(&handler)?);
        unsafe { interop.ShowShareUIForWindow(hwnd) }
    };
    run().is_ok()
}
#[cfg(not(windows))]
pub fn share(_: isize, _: &str, _: &str, _: Option<&str>) -> bool {
    false
}

/// A FILE HANDED UNDER THE NAME THE PAGE SHOWS (iOS MontanaPlayerBar.share, MTDocLink.named): the track's bytes written once under
/// its title in this run's own folder of the temporary place; the path is what the window's thread is handed.
pub fn shared_file(bytes: &[u8], title: &str, ext: &str) -> Option<PathBuf> {
    let clean: String = title.chars().map(|c| if r#"\/:*?"<>|"#.contains(c) || c.is_control() { '_' } else { c }).collect();
    let name = format!("{}.{}", clean.trim().trim_end_matches('.'), ext.trim_start_matches('.'));
    let dir = std::env::temp_dir().join("Montana-share");
    std::fs::create_dir_all(&dir).ok()?;
    let path = dir.join(if name.starts_with('.') { format!("track{name}") } else { name });
    std::fs::write(&path, bytes).ok()?;
    Some(path)
}
/// That file, read where it lies when the sheet asks for it, handed to Windows' own «Поделиться» for this window.
pub fn share_file(owner: isize, title: &str, path: PathBuf) -> bool {
    share_files(owner, title, vec![path])
}
/// Those files, each read where it lies when the sheet asks for them, handed together to Windows' own «Поделиться» (iOS MTShare
/// .present of several URLs).
#[cfg(windows)]
pub fn share_files(owner: isize, title: &str, paths: Vec<PathBuf>) -> bool {
    use windows::core::{Interface, HSTRING};
    use windows::ApplicationModel::DataTransfer::{DataRequestedEventArgs, DataTransferManager};
    use windows::Foundation::TypedEventHandler;
    use windows::Storage::{IStorageItem, StorageFile};
    use windows::Win32::Foundation::HWND;
    use windows::Win32::System::WinRT::RoGetActivationFactory;
    use windows::Win32::UI::Shell::IDataTransferManagerInterop;
    static TOKEN: Mutex<Option<i64>> = Mutex::new(None);
    let title = title.to_string();
    // SAFETY: the interop factory and the manager are COM objects released by their drops; the window handle is this program's own
    let run = || -> windows::core::Result<()> {
        let interop: IDataTransferManagerInterop = unsafe { RoGetActivationFactory(&HSTRING::from("Windows.ApplicationModel.DataTransfer.DataTransferManager"))? };
        let hwnd = HWND(owner as *mut _);
        let manager: DataTransferManager = unsafe { interop.GetForWindow(hwnd)? };
        if let Some(t) = TOKEN.lock().unwrap().take() {
            let _ = manager.RemoveDataRequested(t);
        }
        let handler = TypedEventHandler::<DataTransferManager, DataRequestedEventArgs>::new(move |_, args| {
            if let Some(args) = args.as_ref() {
                let data = args.Request()?.Data()?;
                data.Properties()?.SetTitle(&HSTRING::from(title.as_str()))?;
                let mut items: Vec<Option<IStorageItem>> = vec![];
                for path in &paths {
                    let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path.as_os_str()))?.join()?;
                    items.push(Some(file.cast()?));
                }
                data.SetStorageItemsReadOnly(&windows_collections::IIterable::<IStorageItem>::from(items))?;
            }
            Ok(())
        });
        *TOKEN.lock().unwrap() = Some(manager.DataRequested(&handler)?);
        unsafe { interop.ShowShareUIForWindow(hwnd) }
    };
    run().is_ok()
}
#[cfg(not(windows))]
pub fn share_files(_: isize, _: &str, _: Vec<PathBuf>) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_lent_folder_is_walked_for_its_music_alone() {
        let root = std::env::temp_dir().join(format!("mt-music-{}", crate::wire::hex(&crate::crypto::random(6).unwrap())));
        let deep = root.join("Альбом").join("CD 1");
        std::fs::create_dir_all(&deep).unwrap();
        std::fs::write(root.join("01 Начало.mp3"), b"ID3...").unwrap();
        std::fs::write(deep.join("02 Дальше.FLAC"), b"fLaC...").unwrap();
        std::fs::write(deep.join("cover.jpg"), b"\xff\xd8\xff").unwrap();
        let vault = Vault::at(&root.join("vault")).unwrap();
        assert!(add(&vault, &root));
        assert!(add(&vault, &root), "a folder lent twice is kept once");
        assert_eq!(folders(&vault).len(), 1);
        let tracks = walk(&vault);
        assert_eq!(tracks.iter().map(|t| t.title.as_str()).collect::<Vec<_>>(), vec!["01 Начало", "02 Дальше"]);
        assert_eq!(tracks[1].e, "flac");
        assert!(tracks.iter().all(|t| t.id.starts_with("lent-") && !t.id.contains('\\')), "a track is named by a hash, never its path");
        assert_eq!(bytes(&tracks[0].id).as_deref(), Some(&b"ID3..."[..]));
        assert!(bytes("lent-000000000000000000000000").is_none());
        let _ = std::fs::remove_dir_all(&root);
    }
}
