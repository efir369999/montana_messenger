//! THE BOOK (iOS MTPipeBook + ChatStore; Android Pipes.kt Book, Msg, Chat): the secret of each correspondence, filed under its
//! local name (SHA-256(secret)[0..16] in hex), and the feed of it. Everything is sealed in the device vault; the secrets never
//! leave this machine. The rows keep Android's store names (m, t, o, at, s …) so a copy of a history reads alike.

use crate::vault::Vault;
use crate::wire::{b64, reference, unb64};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::sync::Mutex;

const SECRETS: &str = "pipeSecrets";
const CHATS: &str = "chats";

/// SAVED MESSAGES (iOS savedMessagesKey): the room of the person writing to themselves -- its key English and never translated,
/// no pipe, no wire: nothing there is sent, waits or fails (iOS isLocalRoom). It reaches the identity's other devices as the
/// archive's blocks alone, under the folder of its own key.
pub const SAVED: &str = "Saved Messages";

pub fn is_saved(r: &str) -> bool {
    r == SAVED
}

/// One letter of the feed. `state` is the rung (iOS DeliveryStatus.rung): 0 sending, 1 sent, 2 delivered, 3 read, -1 not sent.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Default)]
pub struct Msg {
    #[serde(rename = "m")]
    pub mid: String,
    #[serde(rename = "t")]
    pub text: String,
    #[serde(rename = "o")]
    pub mine: bool,
    pub at: i64,
    #[serde(rename = "s", default)]
    pub state: i32,
    #[serde(rename = "sa", default)]
    pub status_at: i64,
    /// the quoted letter's words (at most 200) and its mid: a reply (fields 4 and 5 of the body)
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub qt: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub qm: String,
    /// their words changed after the letter came (iOS «edited»)
    #[serde(rename = "ed", default, skip_serializing_if = "std::ops::Not::not")]
    pub edited: bool,
    /// my answer to the letter and theirs (one reaction per person, iOS myReact / peerReact)
    #[serde(rename = "mr", default, skip_serializing_if = "String::is_empty")]
    pub my_react: String,
    #[serde(rename = "pr", default, skip_serializing_if = "String::is_empty")]
    pub peer_react: String,
    /// in a group: who said it ("gm:<group>/<seat>"); empty for mine and for a pair's letters
    #[serde(rename = "fr", default, skip_serializing_if = "String::is_empty")]
    pub from: String,
    /// the card of a link the letter carries (iOS linkPreview: {u, s, t, d, p}), as JSON; empty -- none
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub lp: String,
    /// the author field their letter rode with (iOS Message.authorTag): given back with it when they restore, it proves the
    /// letter theirs by their own key, never by this machine's word
    #[serde(rename = "au", default, skip_serializing_if = "String::is_empty")]
    pub author: String,
}

/// A word of the wire no node took yet: it goes again with the next walk, for a day (iOS queue).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Default)]
pub struct Pending {
    #[serde(rename = "m")]
    pub mid: String,
    #[serde(rename = "t")]
    pub text: String,
    pub at: i64,
}

impl Msg {
    /// THE ONE DOOR TO THE RUNG (iOS ChatStore.advance): only forward; «read» only from «delivered»; «not sent» only from
    /// «sending» or «sent».
    pub fn advance(&mut self, next: i32) -> bool {
        let ok = match next {
            -1 => self.state == 0 || self.state == 1,
            3 => self.state == 2,
            n => n > self.state,
        };
        if ok {
            self.state = next;
            self.status_at = crate::wire::now_ms();
        }
        ok
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Chat {
    #[serde(rename = "ref")]
    pub reference: String,
    #[serde(rename = "n", default)]
    pub name: String,
    /// my own name for them (iOS MTNameBook.manual): it stands over the one they gave themselves; empty -- theirs
    #[serde(rename = "al", default, skip_serializing_if = "String::is_empty")]
    pub alias: String,
    #[serde(rename = "p", default)]
    pub perm: bool,
    #[serde(rename = "u", default)]
    pub unread: u32,
    #[serde(default)]
    pub msgs: Vec<Msg>,
    /// my name as their receipt confirmed it (iOS Announced.recordDelivered): said again only when it changes
    #[serde(rename = "an", default)]
    pub announced: String,
    /// the name on its way: name, the letter's mid and the moment it left; not said twice within the hour (Android annFly)
    #[serde(rename = "af", default)]
    pub name_flight: String,
    /// the birth of the newest letter of mine they said they read (Android PeerRead): a later receipt catches up to it
    #[serde(rename = "pr", default)]
    pub peer_read: i64,
    /// the names of letters taken away: a copy that comes again is answered, never landed (iOS graves)
    #[serde(rename = "gr", default, skip_serializing_if = "Vec::is_empty")]
    pub graves: Vec<String>,
    /// their edits of letters not landed yet (mid, words), at most 32 (iOS held edits)
    #[serde(rename = "he", default, skip_serializing_if = "Vec::is_empty")]
    pub held_edits: Vec<(String, String)>,
    /// the conversation was erased at this birth: nothing born before it lands again (iOS peerFuneral)
    #[serde(rename = "fu", default)]
    pub funeral: i64,
    /// my own erasure for both, waiting for its receipt; then the pipe is forgotten (iOS funeral)
    #[serde(rename = "fm", default, skip_serializing_if = "String::is_empty")]
    pub funeral_mid: String,
    /// out of the list until a letter lands again
    #[serde(rename = "dy", default)]
    pub hidden: bool,
    /// words of the wire waiting for a node
    #[serde(rename = "wq", default, skip_serializing_if = "Vec::is_empty")]
    pub pending: Vec<Pending>,
    /// their face: the birth of the word that set it (0 = none held); a word older than it changes nothing (iOS stateIsCurrent)
    #[serde(rename = "fa", default)]
    pub face_at: i64,
    /// my face as their receipt confirmed it (its tag), and the face on its way: tag, mid, moment (Android annFace2 / annFlyF)
    #[serde(rename = "fs", default, skip_serializing_if = "String::is_empty")]
    pub face_said: String,
    #[serde(rename = "ff", default, skip_serializing_if = "String::is_empty")]
    pub face_flight: String,
    /// my words about myself as their receipt confirmed them, and the ones on their way (tag, mid, moment)
    #[serde(rename = "bs", default, skip_serializing_if = "String::is_empty")]
    pub about_said: String,
    #[serde(rename = "bf", default, skip_serializing_if = "String::is_empty")]
    pub about_flight: String,
    /// their words about themselves (iOS PeerAbout): the bio, the link, the moment they said them
    #[serde(rename = "pb", default, skip_serializing_if = "String::is_empty")]
    pub peer_bio: String,
    #[serde(rename = "pl", default, skip_serializing_if = "String::is_empty")]
    pub peer_link: String,
    #[serde(rename = "pa", default)]
    pub peer_about_at: f64,
    /// the person's own order of the list (iOS pinnedChats, archive, MTQuietChats, the manual unread mark): never said to anyone
    #[serde(rename = "pn", default)]
    pub pinned_at: i64,
    /// the moment the person pinned it last (iOS noteOrder at pinning: «the new one to the very top -- the person's deed»): the
    /// list's order keeps it after the pin is taken off, as iOS never talks a chat's moment down
    #[serde(rename = "oa", default, skip_serializing_if = "unset")]
    pub ordered_at: i64,
    #[serde(rename = "ar", default)]
    pub archived: bool,
    #[serde(rename = "mu", default)]
    pub muted: bool,
    #[serde(rename = "mk", default)]
    pub marked: bool,
    /// blocked (iOS blockedChats): nothing of theirs lands, nothing of mine goes
    #[serde(rename = "bl", default)]
    pub blocked: bool,
    /// the letters pinned in the chat, newest last (iOS pinned per chat; PN: for both)
    #[serde(rename = "pins", default, skip_serializing_if = "Vec::is_empty")]
    pub pins: Vec<String>,
}

impl Chat {
    /// A letter taken away: its row leaves and its name is kept, so a copy never lands (4000 names, the newest kept).
    pub fn bury(&mut self, mid: &str) {
        self.msgs.retain(|m| m.mid != mid);
        if !self.graves.iter().any(|g| g == mid) {
            self.graves.push(mid.to_string());
            if self.graves.len() > 4000 {
                let over = self.graves.len() - 4000;
                self.graves.drain(..over);
            }
        }
    }
}

pub struct Book {
    vault: Vault,
    chats: Mutex<Option<Vec<Chat>>>,
    lock: Mutex<()>,
    /// THE NEWEST CHANGE IS THE ONE ON DISK: every change numbered under the feeds' lock, and a change reaches the disk only if
    /// no later one is there already -- two changes written at once once laid the older last, and a letter left the book at the
    /// next start (found 23.10.2026: a film sent and «Sent» was gone from both feeds after the program was stopped)
    changes: std::sync::atomic::AtomicU64,
    on_disk: Mutex<u64>,
    /// the secrets laid aside are looked for once, at the first read of the secrets (`recover_secrets`)
    secrets_back: std::sync::Once,
}

/// a moment never set is not written
fn unset(n: &i64) -> bool {
    *n == 0
}

/// A letter's name: t<birth ms>-<UUID> (iOS ChatStore.mintMid).
pub fn mint_mid() -> String {
    static LAST: Mutex<i64> = Mutex::new(0);
    let mut last = LAST.lock().unwrap();
    let mut ms = crate::wire::now_ms();
    if ms <= *last {
        ms = *last + 1;
    }
    *last = ms;
    let r = crate::crypto::random(16).unwrap_or_else(|| vec![0; 16]);
    let h = crate::wire::hex(&r).to_uppercase();
    format!("t{ms}-{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32])
}

pub fn birth_ms(mid: &str) -> Option<i64> {
    let core = mid.strip_prefix("mid:").unwrap_or(mid);
    let rest = core.strip_prefix('t')?;
    rest.split('-').next()?.parse().ok()
}

/// THE BOOK'S VALUES READ, OR KEPT ASIDE (the owner's word 24.10.2026: no loss of data): a value that is there but does not open
/// (the machine's seal refused) or does not parse is moved aside, never taken for an empty book the next change would write over
/// every feed and every secret; once it opens again it is merged back (`recover`).
fn read_kept<T: serde::de::DeserializeOwned>(vault: &Vault, name: &str) -> Option<T> {
    match vault.get(name).map(|b| serde_json::from_slice::<T>(&b)) {
        Some(Ok(v)) => Some(v),
        Some(Err(_)) => {
            vault.lay_aside(name);
            None
        }
        None => {
            if vault.has(name) {
                vault.lay_aside(name);
            }
            None
        }
    }
}

/// Two books of one person made one: every chat of either, a chat of both keeps the newer book's state and every letter of the
/// two by its name, the graves of both.
fn merged(mut now: Vec<Chat>, old: Vec<Chat>) -> Vec<Chat> {
    for o in old {
        match now.iter_mut().find(|c| c.reference == o.reference) {
            Some(c) => {
                for m in o.msgs {
                    if !c.msgs.iter().any(|x| x.mid == m.mid) && !c.graves.contains(&m.mid) {
                        c.msgs.push(m);
                    }
                }
                for g in o.graves {
                    if !c.graves.contains(&g) {
                        c.graves.push(g);
                    }
                }
                c.msgs.sort_by_key(|m| m.at);
            }
            None => now.push(o),
        }
    }
    now
}

impl Book {
    pub fn new(vault: Vault) -> Book {
        Book { vault, chats: Mutex::new(None), lock: Mutex::new(()), changes: std::sync::atomic::AtomicU64::new(0), on_disk: Mutex::new(0),
               secrets_back: std::sync::Once::new() }
    }

    fn secrets(&self) -> Map<String, Value> {
        self.secrets_back.call_once(|| self.recover_secrets());
        self.secrets_now()
    }
    fn secrets_now(&self) -> Map<String, Value> {
        match read_kept::<Value>(&self.vault, SECRETS) {
            Some(Value::Object(o)) => o,
            _ => Map::new(),
        }
    }

    /// A BOOK LAID ASIDE COMES BACK (read_kept): the secrets and the feeds that open again are merged into the book that stands,
    /// written, and only then let go; one that still does not open stays aside for the next start. The secrets are read under
    /// the caller's lock, if it holds one: this takes none.
    fn recover_secrets(&self) {
        for name in self.vault.asides(SECRETS) {
            let Some(Value::Object(old)) = self.vault.get(&name).and_then(|b| serde_json::from_slice::<Value>(&b).ok()) else { continue };
            let mut s = self.secrets_now();
            for (k, v) in old {
                s.entry(k).or_insert(v);
            }
            if self.vault.set(SECRETS, Value::Object(s).to_string().as_bytes()) {
                self.vault.delete(&name);
            }
        }
    }
    fn recover(&self, chats: &mut Vec<Chat>) {
        for name in self.vault.asides(CHATS) {
            let Some(old) = self.vault.get(&name).and_then(|b| serde_json::from_slice::<Vec<Chat>>(&b).ok()) else { continue };
            *chats = merged(std::mem::take(chats), old);
            if serde_json::to_vec(&*chats).is_ok_and(|b| self.vault.set(CHATS, &b)) {
                self.vault.delete(&name);
            }
        }
    }

    /// The correspondence of a secret: filed under its local name, kept; the name.
    pub fn establish(&self, secret: &[u8]) -> Option<String> {
        let _g = self.lock.lock().unwrap();
        let r = reference(secret);
        let mut s = self.secrets();
        if !s.contains_key(&r) {
            s.insert(r.clone(), Value::String(b64(secret)));
            if !self.vault.set(SECRETS, Value::Object(s).to_string().as_bytes()) {
                return None;
            }
        }
        Some(r)
    }

    pub fn secret(&self, r: &str) -> Option<Vec<u8>> {
        self.secrets().get(r).and_then(|v| v.as_str()).and_then(unb64)
    }

    pub fn refs(&self) -> Vec<String> {
        self.secrets().keys().cloned().collect()
    }

    fn loaded(&self) -> std::sync::MutexGuard<'_, Option<Vec<Chat>>> {
        let mut g = self.chats.lock().unwrap();
        if g.is_none() {
            let mut chats: Vec<Chat> = read_kept(&self.vault, CHATS).unwrap_or_default();
            self.recover(&mut chats);
            *g = Some(chats);
        }
        g
    }

    /// The feeds as a change left them (`n`, numbered under their lock), laid on disk unless a later change is there already.
    fn keep(&self, n: u64, chats: &[Chat]) {
        let mut on_disk = self.on_disk.lock().unwrap();
        if n <= *on_disk {
            return;
        }
        if let Ok(b) = serde_json::to_vec(chats) {
            if self.vault.set(CHATS, &b) {
                *on_disk = n;
            }
        }
    }
    fn number(&self) -> u64 {
        self.changes.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1
    }

    pub fn all(&self) -> Vec<Chat> {
        self.loaded().clone().unwrap_or_default()
    }

    pub fn chat(&self, r: &str) -> Option<Chat> {
        self.loaded().as_ref()?.iter().find(|c| c.reference == r).cloned()
    }

    /// The name a chat is shown by (iOS displayName: my own word for them first, else the name they gave), its letters left
    /// where they are -- many rows read it at once (the wall's bylines).
    pub fn shown_name(&self, r: &str) -> Option<String> {
        self.loaded().as_ref()?.iter().find(|c| c.reference == r).map(|c| if c.alias.trim().is_empty() { c.name.clone() } else { c.alias.clone() })
    }

    /// The name a correspondent gave themselves (iOS MTNameBook.declared) -- never my own word for them.
    pub fn given_name(&self, r: &str) -> Option<String> {
        self.loaded().as_ref()?.iter().find(|c| c.reference == r).map(|c| c.name.clone())
    }

    /// The chat stands (or its empty name takes the one given); `perm` -- met through a permanent link.
    pub fn open(&self, r: &str, name: &str, perm: bool) {
        self.edit(r, |c| {
            if c.name.is_empty() && !name.is_empty() {
                c.name = name.to_string();
            }
            c.perm |= perm;
        });
    }

    /// One change to one chat, made and kept whole; the chat is born if it is not there.
    pub fn edit(&self, r: &str, f: impl FnOnce(&mut Chat)) {
        let mut g = self.loaded();
        let chats = g.as_mut().unwrap();
        let i = match chats.iter().position(|c| c.reference == r) {
            Some(i) => i,
            None => {
                chats.push(Chat { reference: r.to_string(), ..Default::default() });
                chats.len() - 1
            }
        };
        f(&mut chats[i]);
        let (n, snapshot) = (self.number(), chats.clone());
        drop(g);
        self.keep(n, &snapshot);
    }

    /// One correspondence leaves whole: its secret and its feed (after my erasure for both was heard); the blocks another
    /// device of the person lays for it are not filed here again (iOS deletedCold).
    pub fn drop_chat(&self, r: &str) {
        {
            let _g = self.lock.lock().unwrap();
            let mut gone: Map<String, Value> = self.vault.get(crate::twin::GONE).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
            gone.insert(crate::wire::hex(&crate::wire::sha(&[r.as_bytes()])), Value::Bool(true));
            while gone.len() > 4000 {
                let k = gone.keys().next().cloned().unwrap();
                gone.remove(&k);
            }
            self.vault.set(crate::twin::GONE, Value::Object(gone).to_string().as_bytes());
            let mut s = self.secrets();
            if s.remove(r).is_some() {
                self.vault.set(SECRETS, Value::Object(s).to_string().as_bytes());
            }
        }
        let mut g = self.loaded();
        let chats = g.as_mut().unwrap();
        chats.retain(|c| c.reference != r);
        let (n, snapshot) = (self.number(), chats.clone());
        drop(g);
        self.keep(n, &snapshot);
    }

}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_unreadable_book_is_laid_aside_never_written_over_and_comes_back_when_it_opens() {
        let d = std::env::temp_dir().join(format!("montana-book-aside-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let v = Vault::at(&d).unwrap();
        let b = Book::new(v.clone());
        let secret = vec![5u8; 32];
        let r = b.establish(&secret).unwrap();
        let mid = mint_mid();
        b.edit(&r, |c| c.msgs.push(Msg { mid: mid.clone(), text: "старое".into(), mine: true, at: birth_ms(&mid).unwrap(), ..Default::default() }));
        let (good_chats, good_secrets) = (v.get(CHATS).unwrap(), v.get(SECRETS).unwrap());
        // the machine's seal refuses the feeds, the secrets do not parse: a start reads nothing -- and moves both aside
        std::fs::write(d.join(format!("{CHATS}.sealed")), b"not sealed by this machine").unwrap();
        v.set(SECRETS, b"{broken").then_some(()).unwrap();
        let b2 = Book::new(v.clone());
        assert!(b2.all().is_empty() && b2.secret(&r).is_none(), "nothing readable stands");
        assert_eq!((v.asides(CHATS).len(), v.asides(SECRETS).len()), (1, 1), "both laid aside, not deleted");
        let other = vec![6u8; 32];
        let r2 = b2.establish(&other).unwrap();
        b2.edit(&r2, |c| c.name = "новый".into());
        // the bytes open again (the seal came back): the next start merges them into the book that stands, and lets them go
        for (name, good) in [(v.asides(CHATS)[0].clone(), good_chats), (v.asides(SECRETS)[0].clone(), good_secrets)] {
            assert!(v.set(&name, &good));
        }
        let b3 = Book::new(v.clone());
        assert_eq!(b3.secret(&r), Some(secret));
        assert_eq!(b3.secret(&r2), Some(other));
        assert!(b3.chat(&r).unwrap().msgs.iter().any(|m| m.mid == mid), "the old letter came back");
        assert_eq!(b3.chat(&r2).unwrap().name, "новый", "the newer book's chat stands");
        assert!(v.asides(CHATS).is_empty() && v.asides(SECRETS).is_empty(), "merged, then let go");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn a_pipe_is_filed_by_its_secret_and_its_feed_survives_a_restart() {
        let d = std::env::temp_dir().join(format!("montana-book-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let b = Book::new(Vault::at(&d).unwrap());
        let secret = vec![7u8; 32];
        let r = b.establish(&secret).unwrap();
        assert_eq!(r, reference(&secret));
        b.open(&r, "Боб", true);
        let mid = mint_mid();
        b.edit(&r, |c| c.msgs.push(Msg { mid: mid.clone(), text: "привет".into(), mine: true, at: birth_ms(&mid).unwrap(), state: 1, ..Default::default() }));
        let again = Book::new(Vault::at(&d).unwrap());
        assert_eq!(again.secret(&r), Some(secret));
        let c = again.chat(&r).unwrap();
        assert_eq!((c.name.as_str(), c.perm, c.msgs.len()), ("Боб", true, 1));
        assert!(mid.starts_with('t') && birth_ms(&mid).unwrap() > 1_700_000_000_000);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn changes_made_at_once_are_all_on_disk_after_a_restart() {
        let d = std::env::temp_dir().join(format!("montana-book-race-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let b = std::sync::Arc::new(Book::new(Vault::at(&d).unwrap()));
        let hands: Vec<_> = (0..8).map(|t| {
            let b = b.clone();
            std::thread::spawn(move || {
                for i in 0..25 {
                    let r = format!("chat{}", t % 3);
                    b.edit(&r, |c| c.msgs.push(Msg { mid: format!("m{t}-{i}"), text: "письмо".into(), mine: true, ..Default::default() }));
                }
            })
        }).collect();
        hands.into_iter().for_each(|h| h.join().unwrap());
        // the program stopped and started again: the disk holds every letter of every hand
        let again = Book::new(Vault::at(&d).unwrap());
        let n: usize = again.all().iter().map(|c| c.msgs.len()).sum();
        assert_eq!(n, 8 * 25, "no change lost to an older one written last");
        let left = std::fs::read_dir(&d).unwrap().flatten().filter(|e| e.path().extension().is_some_and(|x| x.to_string_lossy().starts_with("tmp"))).count();
        assert_eq!(left, 0, "no file laid aside is left behind");
        let _ = std::fs::remove_dir_all(&d);
    }
}
