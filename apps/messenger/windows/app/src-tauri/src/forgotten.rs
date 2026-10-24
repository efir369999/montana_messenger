//! THE PERSON LEAVES THIS PLACE, AND NOTHING OF THEIRS WAITS FOR THE NEXT ONE (iOS SeedScope.forget, MTCoinPlace.setAside,
//! MTSeats.leaveForgotten; the owner's word 24.10.2026: identities never mix on one computer, and no data is lost). «Delete
//! account» only marks the folder and starts the program again; the leaving is carried out at the next start, before anything
//! reads the folder -- nothing of the old person lives on in memory to write it back. THE THREE DEEDS APART (the owner's word
//! 24.10.2026 17:0x): a switch of identity keeps each person's folder whole and closed to the others (seats.rs); a backup is the
//! person's own deliberate copy (`.mtbak`), never touched here; the leaving deletes the person's keys, passwords, tokens and every
//! value this machine alone seals (the files, the faces, the recordings -- the next person under the same Windows account could
//! open them), and sets aside what is the identity's value and opens only by its words: the coin book and the TimeChain (the
//! chain on the nodes is the coins' truth and is never touched), the archive sealed under the words. Leaving this computer is not
//! destroying the identity: the same words open the network's history again. The settings and this machine's own stay. No promise
//! is made of bytes wiped from a disk: what goes is unlinked, what stays aside is sealed.

use std::fs;
use std::path::Path;

const MARK: &str = "forget.pending";

/// The settings and this machine's own (iOS settingKeys, markKeys, deviceKeys, keychainStays): they stay for the next person.
const KEEP: &[&str] = &[
    "chatFolders", "copyPlan", "coinsShown", "coinRate.personal", "levelKeepDeleted", "levelRecordCalls", "keepMine", "keepOthers",
    "keepTold", "homeNodeHost", "homeNodePin", "homeNodeOn", "homeKeepDays", "homeCacheLimit", "vpnBook", "vpnHwid", "keepHeld",
    "keepBackAsked", "musicFolders", "musicVolume", "roomsSeen", "blobKeySeed", "lang",
];
/// The identity's value, set aside and read by nothing again (iOS MTCoinPlace.setAside for the coin book): the coins' own records
/// and the archive the words alone open
const ASIDE_KEYS: &[&str] = &["coinLedger", "timechainTip", "coin3", "personSeconds", "fabricV2"];
const ASIDE_DIRS: &[&str] = &["TimeChain", "archive"];
/// What this Windows account alone seals, deleted with the person: another identity of the same account could open it
const GONE_DIRS: &[&str] = &["media", "faces", "recordings", "HomeNode"];
/// The person's own words in the settings file: they leave, the settings stay
const PROFILE_GONE: &[&str] = &["userName", "profileBio", "profileLink"];
/// The list of the files this person opened in the clear (lib.rs OPENED): their copies outside the folder leave too
const OPENED: &str = "openedFiles";

fn now_ms() -> u128 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0)
}

/// The folder is marked: the person leaves at the next start. False when the mark could not be laid.
pub fn mark(folder: &Path) -> bool {
    fs::write(folder.join(MARK), now_ms().to_string()).is_ok()
}

/// A value's name as the vault keeps it: `<name>.sealed`, `<name>.aside<ms>.sealed`, a write's leftover `<name>.tmp...`.
fn value_name(file: &str) -> &str {
    let stem = file.strip_suffix(".sealed").unwrap_or(file);
    let stem = stem.split(".aside").next().unwrap_or(stem);
    stem.split(".tmp").next().unwrap_or(stem)
}

/// THE LEAVING CARRIED OUT (at the start, before the folder is read): first everything worth something goes aside -- if any of it
/// cannot move, nothing is deleted and the mark stays for the next start, the person still here rather than mixed with the next;
/// then every other value of the person goes. True when the folder was marked and the leaving is done.
pub fn carry_out(base: &Path, folder: &Path) -> bool {
    if !folder.join(MARK).exists() {
        return false;
    }
    let aside = base.join("Forgotten").join(now_ms().to_string());
    let vault = folder.join("vault");
    if fs::create_dir_all(aside.join("vault")).is_err() {
        return false;
    }
    let mut moved = true;
    for d in ASIDE_DIRS {
        let from = folder.join(d);
        if from.exists() && fs::rename(&from, aside.join(d)).is_err() {
            moved = false;
        }
    }
    if let Ok(rd) = fs::read_dir(&vault) {
        for e in rd.flatten() {
            let file = e.file_name().to_string_lossy().to_string();
            if ASIDE_KEYS.contains(&value_name(&file)) && fs::rename(e.path(), aside.join("vault").join(&file)).is_err() {
                moved = false;
            }
        }
    }
    if !moved {
        return false;
    }
    // the copies this person opened in the clear (Downloads\Montana): read before the list itself goes
    if let Ok(v) = crate::vault::Vault::at(&vault) {
        let list: Vec<String> = v.get(OPENED).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        for p in list {
            let _ = fs::remove_file(p);
        }
    }
    if let Ok(rd) = fs::read_dir(&vault) {
        for e in rd.flatten() {
            let file = e.file_name().to_string_lossy().to_string();
            if !KEEP.contains(&value_name(&file)) {
                let _ = fs::remove_file(e.path());
            }
        }
    }
    for d in GONE_DIRS {
        let _ = fs::remove_dir_all(folder.join(d));
    }
    let _ = fs::remove_dir_all(std::env::temp_dir().join("Montana-share"));   // the tracks handed to «Share» in passing (music.rs)
    let settings = folder.join("settings.json");
    if let Some(serde_json::Value::Object(mut o)) = fs::read(&settings).ok().and_then(|b| serde_json::from_slice(&b).ok()) {
        for k in PROFILE_GONE {
            o.remove(*k);
        }
        let _ = fs::write(&settings, serde_json::Value::Object(o).to_string());
    }
    fs::remove_file(folder.join(MARK)).is_ok()
}

/// THE SAME WORDS COME BACK TO THIS COMPUTER (iOS: the archive is never deleted -- it stays sealed under the words, and the same
/// words read it again): an archive set aside when a person left, that opens under the words now entered, is theirs -- nobody
/// else's words open it. Its sealed blocks are handed back to be laid as a copy is laid (history::restore), the coin book and the
/// TimeChain set aside beside it return where this folder holds none, and the set-aside place is let go. Nothing that does not open
/// under these words is touched. The blocks brought back; empty when none was these words'.
pub fn bring_back(base: &Path, folder: &Path, now: &crate::history::Archive) -> Vec<Vec<u8>> {
    let Ok(places) = fs::read_dir(base.join("Forgotten")) else { return vec![] };
    let mut back = vec![];
    for place in places.flatten().map(|e| e.path()).filter(|p| p.join("archive").is_dir()) {
        let old = crate::history::Archive::new(&place.join("archive"), now.keys().clone(), [0; 16]);
        let blocks = old.blocks();
        if blocks.is_empty() || now.open_block(&blocks[0]).is_empty() {
            continue; // another person's, or nothing in it: left as it lies
        }
        for k in ASIDE_KEYS {
            let (from, to) = (place.join("vault").join(format!("{k}.sealed")), folder.join("vault").join(format!("{k}.sealed")));
            if from.exists() && !to.exists() {
                let _ = fs::rename(&from, &to);
            }
        }
        if place.join("TimeChain").is_dir() && !folder.join("TimeChain").exists() {
            let _ = fs::rename(place.join("TimeChain"), folder.join("TimeChain"));
        }
        back.extend(blocks);
        let _ = fs::remove_dir_all(&place);
    }
    back
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::Vault;

    #[test]
    fn the_person_leaves_their_secrets_go_the_coins_and_the_archive_wait_aside_and_the_settings_stay() {
        let base = std::env::temp_dir().join(format!("mt-forgotten-{}", crate::wire::hex(&crate::crypto::random(6).unwrap())));
        let v = Vault::at(&base.join("vault")).unwrap();
        for (k, x) in [("mt_active_mnemonic", "words"), ("pipeSecrets", "{}"), ("chats", "[]"), ("coinLedger", "book"), ("passwords", "p"),
                       ("chatFolders", "[]"), ("keepHeld", "{}"), ("groups.held", "{}")] {
            assert!(v.set(k, x.as_bytes()));
        }
        fs::create_dir_all(base.join("archive").join("Chats")).unwrap();
        fs::write(base.join("archive").join("Chats").join("x.mtlog"), b"sealed").unwrap();
        fs::create_dir_all(base.join("TimeChain")).unwrap();
        fs::create_dir_all(base.join("media")).unwrap();
        fs::write(base.join("media").join("x.sealed"), b"a file").unwrap();
        let opened = base.join("opened-copy.txt");
        fs::write(&opened, b"in the clear").unwrap();
        assert!(v.set(OPENED, serde_json::to_vec(&vec![opened.to_string_lossy().to_string()]).unwrap().as_slice()));
        fs::write(base.join("settings.json"), r#"{"userName":"Алиса","profileBio":"о себе","notifSound":false,"AppLanguage":"ru"}"#).unwrap();
        assert!(!carry_out(&base, &base), "an unmarked folder is nobody's leaving");
        assert!(mark(&base));
        assert!(carry_out(&base, &base));
        // the person's values are gone, the settings and the machine's own stay
        for k in ["mt_active_mnemonic", "pipeSecrets", "chats", "groups.held", OPENED] {
            assert!(!v.has(k), "{k} stayed");
        }
        assert!(v.has("chatFolders") && v.has("keepHeld"));
        assert!(!opened.exists(), "the copy opened in the clear stayed");
        let s: serde_json::Value = serde_json::from_slice(&fs::read(base.join("settings.json")).unwrap()).unwrap();
        assert!(s.get("userName").is_none() && s.get("profileBio").is_none());
        assert_eq!((s["notifSound"].as_bool(), s["AppLanguage"].as_str()), (Some(false), Some("ru")));
        // the identity's value waits aside, sealed as it was: the coin book, the archive, the TimeChain
        let aside = fs::read_dir(base.join("Forgotten")).unwrap().flatten().next().unwrap().path();
        let kept = Vault::at(&aside.join("vault")).unwrap();
        assert_eq!(kept.get("coinLedger").as_deref(), Some(&b"book"[..]));
        assert!(!kept.has("passwords") && !v.has("coinLedger") && !v.has("passwords"), "the passwords go, never aside");
        assert!(!base.join("media").exists() && !aside.join("media").exists(), "the files this account alone seals go");
        assert!(aside.join("archive").join("Chats").join("x.mtlog").exists() && !base.join("archive").exists());
        assert!(aside.join("TimeChain").exists() && !base.join("TimeChain").exists());
        assert!(!base.join(MARK).exists(), "the mark is let go once the leaving is done");
        let _ = fs::remove_dir_all(&base);
    }

    #[test]
    fn the_same_words_take_their_archive_back_and_other_words_touch_nothing() {
        let base = std::env::temp_dir().join(format!("mt-forgotten-back-{}", crate::wire::hex(&crate::crypto::random(6).unwrap())));
        let (w1, w2) = (crate::seed::generate().unwrap(), crate::seed::generate().unwrap());
        let a = crate::history::Archive::new(&base.join("archive"), crate::history::keys(&w1).unwrap(), [1; 16]);
        assert!(a.append(crate::book::SAVED, 0, 100, "заметка уходящего".as_bytes()));
        let v = Vault::at(&base.join("vault")).unwrap();
        assert!(v.set("coinLedger", b"book"));
        assert!(mark(&base) && carry_out(&base, &base));
        assert!(!base.join("archive").exists());
        // other words open nothing: the place stays as it lies
        let other = crate::history::Archive::new(&base.join("archive"), crate::history::keys(&w2).unwrap(), [3; 16]);
        assert!(bring_back(&base, &base, &other).is_empty());
        assert_eq!(fs::read_dir(base.join("Forgotten")).unwrap().count(), 1);
        // the same words: the blocks come back to be laid, the coin book returns, the place is let go
        let now = crate::history::Archive::new(&base.join("archive"), crate::history::keys(&w1).unwrap(), [2; 16]);
        let blocks = bring_back(&base, &base, &now);
        assert!(!blocks.is_empty());
        assert!(now.open_block(&blocks[0]).iter().any(|i| i.content == "заметка уходящего".as_bytes()));
        assert_eq!(v.get("coinLedger").as_deref(), Some(&b"book"[..]));
        assert_eq!(fs::read_dir(base.join("Forgotten")).unwrap().count(), 0);
        let _ = fs::remove_dir_all(&base);
    }
}
