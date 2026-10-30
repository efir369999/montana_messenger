//! WHAT A TRACK CARRIES ITSELF (iOS MTTrackMeta): its name, its artist, its length and its cover, read from the file's own tags --
//! ID3, the Vorbis comments of a FLAC (its PICTURE block among them), the iTunes atoms of an MP4, a WAV's -- once per file and
//! kept for the session. A cover past 32 MB is not drawn (iOS coverCap); the picture is handed as it lies, the page draws it down.
//! A lent track is read where it lies, its tags alone; a letter's track from its sealed bytes, never past 64 MB.

use lofty::file::{AudioFile, TaggedFileExt};
use lofty::picture::PictureType;
use lofty::prelude::Accessor;
use serde::Serialize;
use std::collections::HashMap;
use std::sync::Mutex;

#[derive(Clone, Default, Serialize)]
pub struct Meta {
    pub title: Option<String>,
    pub artist: Option<String>,
    /// seconds, 0 when the file does not say
    pub length: f64,
    /// the cover's bytes and their kind, for the page to draw
    #[serde(skip)]
    pub cover: Option<(Vec<u8>, String)>,
}

const COVER_CAP: usize = 32 * 1_048_576;
const LETTER_CAP: usize = 64 * 1_048_576;
static KEPT: Mutex<Option<HashMap<String, Meta>>> = Mutex::new(None);

fn clean(s: Option<std::borrow::Cow<'_, str>>) -> Option<String> {
    s.map(|x| x.trim().to_string()).filter(|x| !x.is_empty())
}

fn of(tagged: &lofty::file::TaggedFile) -> Meta {
    let length = tagged.properties().duration().as_secs_f64();
    let tag = tagged.primary_tag().or_else(|| tagged.first_tag());
    let Some(tag) = tag else { return Meta { length, ..Default::default() } };
    // the front cover first, else the first picture the file carries (a FLAC's other pictures are not its cover)
    let pic = tag.pictures().iter().find(|p| p.pic_type() == PictureType::CoverFront).or_else(|| tag.pictures().first());
    let cover = pic.filter(|p| p.data().len() <= COVER_CAP).map(|p| {
        let mime = p.mime_type().map(|m| m.as_str().to_string()).unwrap_or_else(|| "image/jpeg".into());
        (p.data().to_vec(), mime)
    });
    Meta { title: clean(tag.title()), artist: clean(tag.artist()), length, cover }
}

/// The tags of a file on the disk, read where it lies (a lent folder's track); its folder's picture when the file carries none.
pub fn from_path(path: &std::path::Path) -> Meta {
    let mut m = lofty::read_from_path(path).map(|t| of(&t)).unwrap_or_default();
    if m.cover.is_none() {
        m.cover = folder_art(path);
    }
    m
}
/// THE FOLDER'S PICTURE WHEN THE FILE CARRIES NONE (iOS MTMusicFolders.art, cover(among:)): a picture beside the track, as music
/// players have long chosen it -- the one named for the cover (cover, folder, front, album, albumart, albumartsmall, artwork), else
/// one whose name begins with albumart, else the first by name; never past the cover's cap; a HEIF one drawn as PNG for the window.
pub fn folder_art(track: &std::path::Path) -> Option<(Vec<u8>, String)> {
    let dir = track.parent()?;
    let mut names: Vec<String> = std::fs::read_dir(dir).ok()?.flatten()
        .filter(|e| e.file_type().is_ok_and(|t| t.is_file()))
        .map(|e| e.file_name().to_string_lossy().to_string())
        .filter(|n| matches!(ext_of(n).as_str(), "jpg" | "jpeg" | "png" | "heic" | "webp"))
        .collect();
    names.sort_by_key(|n| n.to_lowercase());
    let stem = |n: &str| n.rsplit_once('.').map(|(s, _)| s).unwrap_or(n).to_lowercase();
    let pick = ["cover", "folder", "front", "album", "albumart", "albumartsmall", "artwork"].iter()
        .find_map(|want| names.iter().find(|n| stem(n) == *want))
        .or_else(|| names.iter().find(|n| stem(n).starts_with("albumart")))
        .or_else(|| names.first())?;
    let path = dir.join(pick);
    if std::fs::metadata(&path).ok()?.len() as usize > COVER_CAP {
        return None;
    }
    let bytes = std::fs::read(&path).ok()?;
    Some(match ext_of(pick).as_str() {
        "heic" => (crate::picture::viewable(bytes), "image/png".into()),
        "png" => (bytes, "image/png".into()),
        "webp" => (bytes, "image/webp".into()),
        _ => (bytes, "image/jpeg".into()),
    })
}
fn ext_of(n: &str) -> String {
    n.rsplit_once('.').map(|(_, e)| e.to_lowercase()).unwrap_or_default()
}

/// The tags of a file's bytes (a letter's track, sealed here).
pub fn from_bytes(bytes: &[u8]) -> Meta {
    if bytes.len() > LETTER_CAP {
        return Meta::default();
    }
    lofty::probe::Probe::new(std::io::Cursor::new(bytes)).guess_file_type().ok()
        .and_then(|p| p.read().ok()).map(|t| of(&t)).unwrap_or_default()
}

/// A track's meta, read once and kept: `read` is asked only when it is not kept yet.
pub fn kept_or(file: &str, read: impl FnOnce() -> Meta) -> Meta {
    if let Some(m) = KEPT.lock().unwrap().as_ref().and_then(|k| k.get(file)) {
        return m.clone();
    }
    let m = read();
    KEPT.lock().unwrap().get_or_insert_with(HashMap::new).insert(file.to_string(), m.clone());
    m
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A WAV of a tone with an ID3 chunk naming its title and artist (the shape a converter writes): read from bytes.
    #[test]
    fn a_wav_says_its_length_and_its_tagged_name() {
        let rate = 8000u32;
        let n = rate as usize; // one second
        let mut pcm = Vec::with_capacity(n * 2);
        for i in 0..n {
            pcm.extend_from_slice(&((8000.0 * (i as f64 * 440.0 * std::f64::consts::TAU / rate as f64).sin()) as i16).to_le_bytes());
        }
        let mut wav = vec![];
        wav.extend_from_slice(b"RIFF");
        wav.extend_from_slice(&(36 + pcm.len() as u32).to_le_bytes());
        wav.extend_from_slice(b"WAVEfmt ");
        wav.extend_from_slice(&16u32.to_le_bytes());
        wav.extend_from_slice(&1u16.to_le_bytes());
        wav.extend_from_slice(&1u16.to_le_bytes());
        wav.extend_from_slice(&rate.to_le_bytes());
        wav.extend_from_slice(&(rate * 2).to_le_bytes());
        wav.extend_from_slice(&2u16.to_le_bytes());
        wav.extend_from_slice(&16u16.to_le_bytes());
        wav.extend_from_slice(b"data");
        wav.extend_from_slice(&(pcm.len() as u32).to_le_bytes());
        wav.extend_from_slice(&pcm);
        let m = from_bytes(&wav);
        assert!((m.length - 1.0).abs() < 0.05, "one second: {}", m.length);
        assert!(m.title.is_none() && m.cover.is_none(), "a bare WAV names nothing");
        assert!(from_bytes(b"not a sound").title.is_none());
        // the same WAV with an «id3 » chunk: an ID3v2.4 tag, TIT2 and TPE1 in UTF-8 (the scene tools\music.ps1 writes the same)
        let frame = |id: &[u8], text: &str| -> Vec<u8> {
            let body = [&[3u8][..], text.as_bytes()].concat();
            [id, &syncsafe(body.len() as u32), &[0, 0], &body].concat()
        };
        let frames = [frame(b"TIT2", "Ля первой октавы"), frame(b"TPE1", "Проверка Montana")].concat();
        let tag = [&b"ID3\x04\x00\x00"[..], &syncsafe(frames.len() as u32), &frames].concat();
        let mut chunk = [&b"id3 "[..], &(tag.len() as u32).to_le_bytes(), &tag].concat();
        if tag.len() % 2 == 1 {
            chunk.push(0);
        }
        let mut tagged = wav.clone();
        tagged.extend_from_slice(&chunk);
        let size = (tagged.len() - 8) as u32;
        tagged[4..8].copy_from_slice(&size.to_le_bytes());
        let m = from_bytes(&tagged);
        assert_eq!((m.title.as_deref(), m.artist.as_deref()), (Some("Ля первой октавы"), Some("Проверка Montana")));
        assert!((m.length - 1.0).abs() < 0.05);
    }

    /// The folder's picture by the names music players look for: «cover» before the rest, a file's own picture first.
    #[test]
    fn a_folder_names_its_cover_as_music_players_do() {
        let dir = std::env::temp_dir().join(format!("mt-art-{}", crate::wire::hex(&crate::crypto::random(6).unwrap())));
        std::fs::create_dir_all(&dir).unwrap();
        let track = dir.join("01 Начало.mp3");
        std::fs::write(&track, b"ID3").unwrap();
        assert!(folder_art(&track).is_none(), "no picture, no cover");
        std::fs::write(dir.join("back.jpg"), b"\xff\xd8back").unwrap();
        assert_eq!(folder_art(&track).unwrap().0, b"\xff\xd8back", "the first by name when none is named for the cover");
        std::fs::write(dir.join("Cover.JPG"), b"\xff\xd8cover").unwrap();
        std::fs::write(dir.join("folder.png"), b"\x89PNGfolder").unwrap();
        let (b, mime) = folder_art(&track).unwrap();
        assert_eq!((b.as_slice(), mime.as_str()), (&b"\xff\xd8cover"[..], "image/jpeg"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn syncsafe(n: u32) -> [u8; 4] {
        [((n >> 21) & 0x7f) as u8, ((n >> 14) & 0x7f) as u8, ((n >> 7) & 0x7f) as u8, (n & 0x7f) as u8]
    }
}
