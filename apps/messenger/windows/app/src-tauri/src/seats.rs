//! THE PERSONS OF MONTANA ON ONE COMPUTER (iOS MTSeats, MontanaSeats.swift; the author's words 29.09.2026 «Montana creates a second
//! identity with the possibility to switch», 30.09 «it creates a new one and leaves the old one untouched», 07.10 «the extra
//! accounts are dead until I enter them -- a critical error»).
//!
//! A seat is a person on this computer, each in a data folder of its own: the first person where Montana always kept its data,
//! every other one under `Seats\<id>` beside it -- their vault, their media, their window's storage. Nothing moves between the
//! folders and nothing of a person is deleted: a move is the book naming another seat and the program starting again in that
//! person's folder. The book is sealed like every value of a person (DPAPI, this Windows user alone).
//!
//! THE PERSONS ON THE SHELF ARE ALIVE (iOS MTShelfPost): every person not seated runs as a Montana process of their own with no
//! window (`--shelf <id>`) -- their letters land, are receipted and ring under their name, their queue rides, their coins and
//! their wall go on. A folder is held by one process at a time (its lock file); a person on the shelf leaves when they are seated,
//! when their seat leaves the book, or when no window's process has stood for half a minute.
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Seat {
    pub id: String,
    pub born: i64,
    /// the name and the glyph the person wore when they last left the seat, for the drawer's face
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub glyph: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Book {
    pub active: Option<String>,
    /// the person who left the seat last: the first screen's cross brings them back (iOS returnToLast)
    pub last: Option<String>,
    /// the seat that lives in the base folder itself: the person who was here before there were seats
    pub root: Option<String>,
    pub seats: Vec<Seat>,
    /// the seat stands empty to make a person (iOS adding): the first screen opens on the Montana road, with the way back
    #[serde(default)]
    pub adding: bool,
    /// my page's ground carried into the seat emptied for a new person (iOS MTWallpaper.carry, 03.10)
    #[serde(default)]
    pub carry: Option<String>,
}

/// Where this process stands: the base folder, its seat and that seat's folder, and whether it is a person on the shelf.
pub struct Here {
    pub base: PathBuf,
    pub seat: Option<String>,
    pub folder: PathBuf,
    pub shelf: bool,
}
static HERE: OnceLock<Here> = OnceLock::new();
/// The folder's lock and, for the window's process, the base's: held for the life of the process.
static HELD: std::sync::Mutex<Vec<std::fs::File>> = std::sync::Mutex::new(Vec::new());

const LOCK: &str = ".seat.lock";
const FRONT_LOCK: &str = ".front.lock";
/// The window's process writes its id here: a check follows the program across a move by it.
pub const FRONT_PID: &str = "front.pid";
/// Montana opened a second time asks the window standing to come forward, and leaves.
pub const SHOW: &str = "show.request";

/// The base folder: a check's own (MONTANA_DATA_DIR), or the app's local data, as Tauri names it (<LOCALAPPDATA>\<identifier>).
pub fn base_of(identifier: &str) -> PathBuf {
    if let Some(d) = std::env::var_os("MONTANA_DATA_DIR") {
        return PathBuf::from(d);
    }
    let local = std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    local.join(identifier)
}

/// The book's own vault, beside the seats' folders (not in «Seats»: Windows names ignore case).
fn vault(base: &Path) -> Option<crate::vault::Vault> {
    crate::vault::Vault::at(&base.join("seatbook")).ok()
}

pub fn book(base: &Path) -> Book {
    vault(base).and_then(|v| v.get("book")).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

/// The book written and read back (iOS write): a move runs only on a book that landed.
pub fn write(base: &Path, b: &Book) -> bool {
    let Some(v) = vault(base) else { return false };
    let Ok(bytes) = serde_json::to_vec(b) else { return false };
    v.set("book", &bytes) && v.get("book").as_deref() == Some(&bytes[..])
}

pub fn folder(base: &Path, b: &Book, id: &str) -> PathBuf {
    if b.root.as_deref() == Some(id) { base.to_path_buf() } else { base.join("Seats").join(id) }
}

/// A seat's name: a folder of this computer, drawn by the core's own randomness (iOS newId: four bytes in hex).
fn new_id(b: &Book) -> String {
    loop {
        let r = crate::crypto::random(4).unwrap_or_else(|| crate::wire::now_ms().to_le_bytes()[..4].to_vec());
        let id = crate::wire::hex(&r);
        if !b.seats.iter().any(|s| s.id == id) {
            return id;
        }
    }
}

/// The person seated before seats were used takes a seat of their own at the first move (iOS seatForActive).
fn seat_for_active(b: &mut Book) -> String {
    if let Some(a) = b.active.clone() {
        return a;
    }
    let id = new_id(b);
    b.seats.push(Seat { id: id.clone(), born: crate::wire::now_ms(), ..Default::default() });
    b.root = Some(id.clone());
    b.active = Some(id.clone());
    id
}

/// The words a seat's folder holds (read to tell a person who comes back by their words, never written anywhere).
fn words_in(folder: &Path) -> Option<String> {
    crate::seed::Seed::new(crate::vault::Vault::at(&folder.join("vault")).ok()?).mnemonic()
}

/// Which folder this process opens: a person on the shelf their own, the window's process the seated person's (or the base,
/// before there are seats). Called once, before anything reads a folder.
pub fn settle(identifier: &str) -> &'static Here {
    HERE.get_or_init(|| {
        let base = base_of(identifier);
        let _ = std::fs::create_dir_all(&base);
        let args: Vec<String> = std::env::args().collect();
        let shelf = args.iter().position(|a| a == "--shelf").and_then(|i| args.get(i + 1)).cloned();
        let b = book(&base);
        let (seat, shelf) = match shelf {
            Some(id) if b.seats.iter().any(|s| s.id == id) => (Some(id), true),
            Some(_) => std::process::exit(0), // a seat no longer in the book has nobody to serve
            None => (b.active.clone().filter(|a| b.seats.iter().any(|s| &s.id == a)), false),
        };
        let folder = seat.as_deref().map_or_else(|| base.clone(), |id| folder(&base, &b, id));
        let _ = std::fs::create_dir_all(&folder);
        crate::forgotten::carry_out(&base, &folder);   // a person who left: carried out before anything reads the folder
        Here { base, seat, folder, shelf }
    })
}

pub fn here() -> Option<&'static Here> {
    HERE.get()
}

/// A file opened for this process alone: the folder it stands for is held while it lives.
fn take_lock(path: &Path) -> Option<std::fs::File> {
    let mut o = std::fs::OpenOptions::new();
    o.create(true).write(true);
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        o.share_mode(0);
    }
    o.open(path).ok()
}
fn free(path: &Path) -> bool {
    take_lock(path).is_some()
}

/// The folder taken for this process. A person on the shelf finding their folder held leaves: another process serves them. The
/// window's process takes the window's lock first -- a second window of Montana for the same computer leaves (a move's old
/// window is gone within a second, so only one still standing after three is another) -- then the person's folder, which a
/// person on the shelf being seated lets go within seconds.
pub fn hold(h: &Here) -> bool {
    if h.shelf {
        let Some(f) = take_lock(&h.folder.join(LOCK)) else { return false };
        HELD.lock().unwrap().push(f);
        return true;
    }
    let mut front = None;
    for _ in 0..12 {
        front = take_lock(&h.base.join(FRONT_LOCK));
        if front.is_some() {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(250));
    }
    let Some(front) = front else { return false };
    HELD.lock().unwrap().push(front);
    let _ = std::fs::write(h.base.join(FRONT_PID), std::process::id().to_string());
    for _ in 0..40 {
        if let Some(f) = take_lock(&h.folder.join(LOCK)) {
            HELD.lock().unwrap().push(f);
            return true;
        }
        std::thread::sleep(std::time::Duration::from_millis(500));
    }
    // a process that never lets the folder go: the window opens all the same, as it did before there were seats
    true
}

/// What the drawer shows: every person waiting on the shelf, with the face their folder keeps.
#[derive(Serialize, Debug)]
pub struct Parked {
    pub id: String,
    pub name: String,
    pub glyph: String,
    /// the person's own face (a JPEG in base64), when they chose one
    pub face: Option<String>,
}
#[derive(Serialize, Debug)]
pub struct Shown {
    pub parked: Vec<Parked>,
    pub adding: bool,
    /// the seat stands empty and somebody waits on the shelf: the first screen's cross brings them back
    pub can_return: bool,
    pub shelf: bool,
    pub carry: Option<String>,
}

pub fn shown(h: &Here, seated: bool) -> Shown {
    let b = book(&h.base);
    let parked = b.seats.iter().filter(|s| Some(&s.id) != h.seat.as_ref()).map(|s| {
        let f = folder(&h.base, &b, &s.id);
        let face = crate::vault::Vault::at(&f.join("vault")).ok().and_then(|v| v.get("selfFace")).filter(|x| !x.is_empty())
            .map(|x| crate::wire::b64(&x));
        let name = if s.name.trim().is_empty() { crate::profile::Profile::at(&f).read().user_name } else { s.name.clone() };
        Parked { id: s.id.clone(), glyph: if s.glyph.is_empty() { name.chars().next().map(String::from).unwrap_or_default() } else { s.glyph.clone() },
                 name, face }
    }).filter(|p| words_in(&folder(&h.base, &b, &p.id)).is_some()).collect::<Vec<_>>();
    Shown { can_return: !seated && !parked.is_empty(), parked, adding: b.adding, shelf: h.shelf, carry: if seated { None } else { b.carry.clone() } }
}

/// The words of a person waiting on the shelf (iOS MTSeats.shelfCoins): read for a transfer to oneself on that account, never
/// written anywhere; none for the person seated.
pub fn shelf_words(h: &Here, id: &str) -> Option<String> {
    let b = book(&h.base);
    if h.seat.as_deref() == Some(id) || !b.seats.iter().any(|s| s.id == id) {
        return None;
    }
    words_in(&folder(&h.base, &b, id))
}
/// A person waiting on the shelf: their vault and the name the drawer shows.
pub fn shelf_vault(h: &Here, id: &str) -> Option<(crate::vault::Vault, String)> {
    let b = book(&h.base);
    let s = b.seats.iter().find(|s| s.id == id)?;
    let f = folder(&h.base, &b, id);
    let name = if s.name.trim().is_empty() { crate::profile::Profile::at(&f).read().user_name } else { s.name.clone() };
    Some((crate::vault::Vault::at(&f.join("vault")).ok()?, name))
}

/// A pipe handed to a person on the shelf, waiting for their own process to take it: «shelfMet_<tag>» in their vault.
const MET: &str = "shelfMet_";

/// THE PAIR OF TWO PERSONS OF THIS COMPUTER (iOS MTSeats.pairWithShelf; the author's word 11.10.2026 17:13 MSK, No.62: «with several
/// accounts, an option in a transfer to send to oneself on another account»): the person seated meets a person on the shelf here,
/// on the computer that holds both -- an encapsulation to that person's own card, accepted by the card's own key -- so the pipe is
/// born in the seated book and handed to the person on the shelf, with no node in the meeting; their own process takes it
/// (`take_met`). A pipe the two already share is found first. The pipe's name.
pub fn pair_with_shelf(h: &Here, id: &str, mine: &crate::book::Book, my_name: &str) -> Option<String> {
    if shelf_words(h, id).is_none() {
        crate::trace_line(&format!("seat_pair refused seat={id} -- not waiting on the shelf"));
        return None;
    }
    let (v, name) = shelf_vault(h, id)?;
    let r = pair_with(&v, &name, mine, my_name);
    crate::trace_line(&match &r {
        Some(r) => format!("seat_pair seat={id} conv={}", &r[..r.len().min(10)]),
        None => format!("seat_pair refused seat={id} -- no card of theirs opens"),
    });
    r
}
/// The meeting itself, with the other person's vault and name: the pipe the two share, or one born to their card and handed to them.
fn pair_with(v: &crate::vault::Vault, name: &str, mine: &crate::book::Book, my_name: &str) -> Option<String> {
    let theirs = crate::book::Book::new(v.clone());
    let mut held: Vec<Vec<u8>> = theirs.refs().iter().filter_map(|r| theirs.secret(r)).collect();
    held.extend(met(v).into_iter().map(|(_, s, _)| s));
    if let Some(r) = mine.refs().into_iter().find(|r| mine.secret(r).is_some_and(|s| held.contains(&s))) {
        return Some(r);
    }
    for (root, sk) in (crate::card::Card { vault: v }).own_keys() {
        let Some((ct, ss)) = crate::crypto::mlkem_encaps(&root) else { continue };
        let Some(secret) = crate::crypto::first_secret(&ss, &root, &ct) else { continue };
        // accepted by the card's own key, as their own device would accept it
        let back = crate::crypto::mlkem_decaps(&sk, &ct).and_then(|s2| crate::crypto::first_secret(&s2, &root, &ct));
        if back.as_deref() != Some(&secret[..]) {
            continue;
        }
        let Some(r) = mine.establish(&secret) else { continue };
        let tag = crate::wire::hex(&crate::wire::sha(&[&secret]))[..16].to_string();
        let handed = serde_json::json!({ "s": crate::wire::b64(&secret), "n": my_name.trim() }).to_string();
        if !v.set(&format!("{MET}{tag}"), handed.as_bytes()) {
            mine.drop_chat(&r);
            continue;
        }
        mine.open(&r, name, false);
        return Some(r);
    }
    None
}

/// The pipes handed to this vault's person: (the entry's name, the secret, the name of the one who met them).
fn met(v: &crate::vault::Vault) -> Vec<(String, Vec<u8>, String)> {
    let Ok(dir) = std::fs::read_dir(v.dir()) else { return vec![] };
    dir.flatten().filter_map(|e| e.file_name().to_str().and_then(|n| n.strip_suffix(".sealed")).filter(|n| n.starts_with(MET)).map(str::to_string))
        .filter_map(|n| {
            let o: serde_json::Value = serde_json::from_slice(&v.get(&n)?).ok()?;
            let s = o["s"].as_str().and_then(crate::wire::unb64).filter(|s| !s.is_empty())?;
            Some((n, s, o["n"].as_str().unwrap_or("").to_string()))
        }).collect()
}
/// THE PIPES A PERSON WAS MET BY HERE ARE BORN IN THEIR OWN BOOK (iOS landShelf, the author's word 11.10.2026 19:0x MSK): every pipe
/// another person of this computer handed to this one stands in this person's book with the name of the one who met them, and
/// its entry leaves. The pipes taken.
pub fn take_met(v: &crate::vault::Vault, mine: &crate::book::Book) -> usize {
    let mut born = 0;
    for (n, secret, name) in met(v) {
        let Some(r) = mine.establish(&secret) else { continue };
        mine.open(&r, &name, false);
        v.delete(&n);
        born += 1;
    }
    if born > 0 {
        crate::trace_line(&format!("shelf_met pipes={born}"));
    }
    born
}

/// The name and the glyph the person seated wears now, written into their seat for the drawer of the others (iOS park).
pub fn note_face(h: &Here, name: &str) {
    let mut b = book(&h.base);
    let Some(id) = h.seat.clone().or_else(|| (!b.seats.is_empty()).then(|| seat_for_active(&mut b))) else { return };
    if let Some(s) = b.seats.iter_mut().find(|s| s.id == id) {
        let glyph = name.trim().chars().next().map(String::from).unwrap_or_default();
        if s.name != name.trim() || s.glyph != glyph {
            s.name = name.trim().to_string();
            s.glyph = glyph;
            write(&h.base, &b);
        }
    }
}

#[derive(Debug, PartialEq)]
pub enum Refused {
    Unknown,
    Storage,
}

/// The drawer's face of a person on the shelf: the book names them, and the program starts again in their folder.
pub fn switch_to(h: &Here, id: &str) -> Result<(), Refused> {
    let mut b = book(&h.base);
    if !b.seats.iter().any(|s| s.id == id) || h.seat.as_deref() == Some(id) || words_in(&folder(&h.base, &b, id)).is_none() {
        return Err(Refused::Unknown);
    }
    let from = seat_for_active(&mut b);
    b.last = Some(from);
    b.active = Some(id.to_string());
    b.adding = false;
    b.carry = None;
    if write(&h.base, &b) { Ok(()) } else { Err(Refused::Storage) }
}

/// THE MONTANA DOOR BESIDE A PERSON SEATED (iOS makeRoom): that person goes to the shelf, never wiped, and a seat stands empty
/// for the new person, my page's ground carried into it.
pub fn make_room(h: &Here, carry: Option<String>) -> Result<String, Refused> {
    let mut b = book(&h.base);
    let from = seat_for_active(&mut b);
    let id = new_id(&b);
    b.seats.push(Seat { id: id.clone(), born: crate::wire::now_ms(), ..Default::default() });
    b.last = Some(from);
    b.active = Some(id.clone());
    b.adding = true;
    b.carry = carry;
    let _ = std::fs::create_dir_all(folder(&h.base, &b, &id));
    if write(&h.base, &b) { Ok(id) } else { Err(Refused::Storage) }
}

/// The first screen's cross (iOS returnToLast): the empty seat leaves the book, the person who waited last is seated again.
pub fn return_to_last(h: &Here) -> Result<(), Refused> {
    let mut b = book(&h.base);
    let me = h.seat.clone().ok_or(Refused::Unknown)?;
    if words_in(&h.folder).is_some() {
        return Err(Refused::Unknown);
    }
    b.seats.retain(|s| s.id != me);
    let back = b.last.clone().filter(|l| b.seats.iter().any(|s| &s.id == l)).or_else(|| b.seats.first().map(|s| s.id.clone()));
    let Some(back) = back else { return Err(Refused::Unknown) };
    b.active = Some(back);
    b.last = None;
    b.adding = false;
    b.carry = None;
    if write(&h.base, &b) { Ok(()) } else { Err(Refused::Storage) }
}

/// THE WORDS OF A PERSON WAITING ON THE SHELF LIFT THAT SEAT (iOS MTSeats.lift): typed on an empty seat, they seat that person
/// again, and no second copy of them is born. The empty seat leaves the book. Some(id) when such a person waits.
pub fn lift(h: &Here, words: &str) -> Option<String> {
    let mut b = book(&h.base);
    let me = h.seat.clone()?;
    if words_in(&h.folder).is_some() {
        return None;
    }
    let typed = crate::seed::normal(words);
    let found = b.seats.iter().filter(|s| s.id != me)
        .find(|s| words_in(&folder(&h.base, &b, &s.id)).is_some_and(|w| crate::seed::normal(&w) == typed))?.id.clone();
    b.seats.retain(|s| s.id != me);
    b.active = Some(found.clone());
    b.adding = false;
    b.carry = None;
    write(&h.base, &b).then_some(found)
}

/// A person born on the empty seat: the making is done, the first screen asks no more (iOS doneAdding / born).
pub fn born(h: &Here) {
    let mut b = book(&h.base);
    if b.adding || b.carry.is_some() {
        b.adding = false;
        b.carry = None;
        write(&h.base, &b);
    }
}

/// Folders under Seats that the book names no more and that hold no person: an empty seat left by its cross, swept by the next
/// window's process (its web view's files were open while it stood). A folder that holds words is never touched.
pub fn sweep(h: &Here) {
    // A BOOK THAT DOES NOT OPEN NAMES NOTHING, AND SWEEPS NOTHING (the owner's word 24.10.2026: no loss of data): a refusal of the
    // machine's seal once read as an empty book and took every seat's folder, archives and all
    let Some(v) = vault(&h.base) else { return };
    if v.has("book") && v.get("book").and_then(|b| serde_json::from_slice::<Book>(&b).ok()).is_none() {
        return;
    }
    let b = book(&h.base);
    let Ok(rd) = std::fs::read_dir(h.base.join("Seats")) else { return };
    for e in rd.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        // a folder whose words are there, open or not, holds a person: never touched
        let words_kept = e.path().join("vault").join(format!("{}.sealed", crate::seed::MN)).exists();
        if b.seats.iter().any(|s| s.id == name) || words_kept || words_in(&e.path()).is_some() || !free(&e.path().join(LOCK)) {
            continue;
        }
        let _ = std::fs::remove_dir_all(e.path());
    }
}

/// THE SHELF COMES ALIVE: every person waiting whose folder no process holds gets a process of their own, with no window.
pub fn wake_shelf(h: &Here) {
    if h.shelf {
        return;
    }
    let b = book(&h.base);
    let Ok(exe) = std::env::current_exe() else { return };
    for s in b.seats.iter().filter(|s| Some(&s.id) != h.seat.as_ref()) {
        let f = folder(&h.base, &b, &s.id);
        if words_in(&f).is_none() || !free(&f.join(LOCK)) {
            continue;
        }
        let mut c = std::process::Command::new(&exe);
        c.arg("--shelf").arg(&s.id).env_remove("WEBVIEW2_USER_DATA_FOLDER");
        let _ = c.spawn();
    }
}

/// Whether a person on the shelf should leave now: seated (the window's process takes the folder), out of the book, or no window
/// standing for `grace` checks in a row.
pub fn shelf_leaves(h: &Here, gone_for: &mut u32) -> bool {
    let b = book(&h.base);
    let Some(me) = h.seat.as_ref() else { return true };
    if b.active.as_ref() == Some(me) || !b.seats.iter().any(|s| &s.id == me) {
        return true;
    }
    if free(&h.base.join(FRONT_LOCK)) { *gone_for += 1 } else { *gone_for = 0 }
    *gone_for >= 15
}

#[cfg(test)]
mod tests {
    use super::*;

    fn here_at(base: &Path, b: &Book, seat: Option<&str>) -> Here {
        let folder = seat.map_or_else(|| base.to_path_buf(), |id| folder(base, b, id));
        Here { base: base.to_path_buf(), seat: seat.map(String::from), folder, shelf: false }
    }

    #[test]
    fn a_book_that_does_not_open_sweeps_no_folder() {
        let base = std::env::temp_dir().join(format!("mt-seats-{}", crate::wire::hex(&crate::crypto::random(6).unwrap())));
        let seat = base.join("Seats").join("someone");
        std::fs::create_dir_all(seat.join("vault")).unwrap();
        std::fs::create_dir_all(base.join("seatbook")).unwrap();
        // the machine's seal refuses the book: it reads as nothing -- and nothing goes
        std::fs::write(base.join("seatbook").join("book.sealed"), b"not sealed by this machine").unwrap();
        sweep(&here_at(&base, &Book::default(), None));
        assert!(seat.exists(), "an unreadable book took a folder");
        // the book opens and names nobody, and the folder's words are there though they do not open: still a person's folder
        assert!(write(&base, &Book::default()));
        std::fs::write(seat.join("vault").join(format!("{}.sealed", crate::seed::MN)), b"sealed elsewhere").unwrap();
        sweep(&here_at(&base, &Book::default(), None));
        assert!(seat.exists(), "a folder that holds words was swept");
        // no words at all: an empty seat left by its cross goes
        std::fs::remove_file(seat.join("vault").join(format!("{}.sealed", crate::seed::MN))).unwrap();
        sweep(&here_at(&base, &Book::default(), None));
        assert!(!seat.exists());
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn a_room_made_then_given_back_leaves_the_first_person_where_they_were() {
        let base = std::env::temp_dir().join(format!("mt-seats-{}", crate::wire::hex(&crate::crypto::random(6).unwrap())));
        std::fs::create_dir_all(&base).unwrap();
        // the first person, before there were seats, lives in the base folder
        let h = here_at(&base, &Book::default(), None);
        let id = make_room(&h, Some("named:sky".into())).unwrap();
        let b = book(&base);
        let root = b.root.clone().unwrap();
        assert_eq!(folder(&base, &b, &root), base, "the first person's folder is the base itself");
        assert_eq!(b.active.as_deref(), Some(id.as_str()));
        assert_eq!(b.last.as_deref(), Some(root.as_str()));
        assert!(b.adding);
        assert_eq!(folder(&base, &b, &id), base.join("Seats").join(&id));
        // the new seat's cross: the empty seat goes, the first person is seated again
        let h2 = here_at(&base, &b, Some(&id));
        let shown = shown(&h2, false);
        assert!(shown.parked.is_empty(), "nobody waits with words in the folder: the first person here holds none in this test");
        assert_eq!(shown.carry.as_deref(), Some("named:sky"));
        return_to_last(&h2).unwrap();
        let b = book(&base);
        assert_eq!(b.active.as_deref(), Some(root.as_str()));
        assert!(!b.adding && b.carry.is_none());
        assert!(!b.seats.iter().any(|s| s.id == id));
        // the folder the book names no more is swept, and never one that holds a person
        sweep(&here_at(&base, &b, Some(&root)));
        assert!(!base.join("Seats").join(&id).exists());
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn a_folder_is_held_by_one_process_at_a_time() {
        let dir = std::env::temp_dir().join(format!("mt-lock-{}", crate::wire::hex(&crate::crypto::random(6).unwrap())));
        std::fs::create_dir_all(&dir).unwrap();
        let a = take_lock(&dir.join(LOCK)).expect("the first takes it");
        assert!(take_lock(&dir.join(LOCK)).is_none(), "a second is refused while the first holds it");
        drop(a);
        assert!(free(&dir.join(LOCK)), "let go, it is free");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn two_persons_of_one_computer_meet_by_a_card_with_no_node_and_share_one_pipe() {
        let dir = std::env::temp_dir().join(format!("mt-pair-{}", crate::wire::hex(&crate::crypto::random(6).unwrap())));
        let (va, vb) = (crate::vault::Vault::at(&dir.join("a")).unwrap(), crate::vault::Vault::at(&dir.join("b")).unwrap());
        let (a, b) = (crate::book::Book::new(va.clone()), crate::book::Book::new(vb.clone()));
        assert_eq!(pair_with(&vb, "Б", &a, "А"), None, "no card of theirs: no pipe");
        (crate::card::Card { vault: &vb }).offer_permanent("Б").unwrap();   // the unit tests lay nothing on a node
        let r = pair_with(&vb, "Б", &a, "А").expect("their card opens");
        assert_eq!(a.chat(&r).map(|c| c.name).as_deref(), Some("Б"));
        assert!(b.secret(&r).is_none(), "handed, not yet taken by their own process");
        assert_eq!(pair_with(&vb, "Б", &a, "А").as_deref(), Some(r.as_str()), "a pipe handed and not yet taken is the one they share");
        assert_eq!(take_met(&vb, &b), 1);
        assert_eq!((b.secret(&r), b.chat(&r).map(|c| c.name)), (a.secret(&r), Some("А".to_string())), "one secret, one name on both sides");
        assert_eq!(take_met(&vb, &b), 0, "taken once");
        assert_eq!(pair_with(&vb, "Б", &a, "А").as_deref(), Some(r.as_str()), "the pipe the two share is found first");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
