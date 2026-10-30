//! MY PAGE'S GROUND ON A CORRESPONDENT'S SCREEN (iOS MTPageGround, MontanaFeeds.swift; E2E.sendGroundIfNeeded): the ground rides
//! as my words about myself do -- one silent letter «PG:» {"g", "at"} whose content is "" for none, "n:" + a drawn ground's name, or
//! "p:" + the picture as it is kept, light; only to a correspondent whose build is proven to read it (their presence word speaks
//! «G»), again when the tag of what they hold of mine («G» in their word) differs. A correspondent's ground is kept here, the
//! latest word winning, and drawn on their page.

use crate::presence::wire_tag;
use crate::vault::Vault;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Mutex;

pub const MARK: &str = "\u{200B}\u{200B}PG:";
const KEY: &str = "pageGround";
/// a received picture's bytes, at most (iOS limit)
const LIMIT: usize = 4_000_000;
/// a light picture of mine: within the budget a letter's cargo carries (iOS lightBudget)
const LIGHT: usize = 3_000_000;
/// The drawn grounds a word may name (iOS 2304 MTWallpaper.names): the gold is gone whole (MTWallpaper.retired).
pub const NAMES: [&str; 12] = ["montana", "default", "black", "dark", "blue", "sky", "dusk", "water", "aurora", "burgundy", "rose", "forest"];
/// A ground told under a retired name wears the default ground (iOS MTWallpaper.parse).
const RETIRED: [&str; 1] = ["gold"];

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Theirs {
    /// the tag of what they said, and the moment they said it
    pub tag: String,
    pub at: f64,
    /// a drawn ground's name, or the media store's name of their picture; both empty -- none
    #[serde(default)]
    pub named: String,
    #[serde(default)]
    pub photo: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
struct Store {
    /// my ground's content as it rides; None -- nothing chosen yet: the default ground, as iOS 2304's (byDefault)
    mine: Option<String>,
    #[serde(default)]
    cap: Vec<String>,
    /// the tag each correspondent took of mine (the network took the letter)
    #[serde(default)]
    sent: HashMap<String, String>,
    #[serde(default)]
    theirs: HashMap<String, Theirs>,
}

#[derive(Default)]
struct Live {
    store: Option<Store>,
    healed_at: HashMap<String, i64>,
    /// a letter that did not leave is tried again after a minute, not at every walk
    tried_at: HashMap<String, (String, i64)>,
}

static LIVE: Mutex<Option<HashMap<String, Live>>> = Mutex::new(None);

fn with<R>(vault: &Vault, f: impl FnOnce(&mut Live, &mut Store) -> R) -> R {
    let mut g = LIVE.lock().unwrap();
    let live = g.get_or_insert_with(HashMap::new).entry(vault.dir().to_string_lossy().to_string()).or_default();
    if live.store.is_none() {
        live.store = Some(vault.get(KEY).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default());
    }
    let mut s = live.store.take().unwrap();
    let r = f(live, &mut s);
    live.store = Some(s);
    r
}

fn save(vault: &Vault, s: &Store) {
    if let Ok(b) = serde_json::to_vec(s) {
        vault.set(KEY, &b);
    }
}

/// One tag for a page's ground (iOS groundTag): the name's digest of the content; none -- «0».
pub fn tag(g: &str) -> String {
    if g.is_empty() { "0".into() } else { wire_tag(g.as_bytes()) }
}

fn mine_of(s: &Store) -> String {
    s.mine.clone().unwrap_or_else(|| "n:default".into())
}

/// A light picture: JPEG or HEIC, within the budget (iOS isLight).
pub fn is_light(d: &[u8]) -> bool {
    d.len() >= 12 && d.len() <= LIGHT && (d.starts_with(&[0xFF, 0xD8, 0xFF]) || &d[4..8] == b"ftyp")
}

/// My page's ground chosen on this machine: none, a drawn one, or my picture as it is kept.
pub fn set_mine(vault: &Vault, g: String) {
    with(vault, |_, s| {
        if s.mine.as_deref() != Some(g.as_str()) {
            s.mine = Some(g);
            save(vault, s);
        }
    });
}

/// What my presence word says after the wall's version (iOS «G» + heldTag): the tag of their ground I hold; once read this run.
pub fn tail_at(dir: &str, conv: &str) -> String {
    let mut g = LIVE.lock().unwrap();
    let Some(s) = g.as_mut().and_then(|m| m.get_mut(dir)).and_then(|l| l.store.as_ref()) else { return String::new() };
    format!("G{}", s.theirs.get(conv).map(|t| t.tag.clone()).unwrap_or_else(|| "0".into()))
}

/// Read once at the walk's start, so my word names what I hold.
pub fn seat(vault: &Vault) {
    with(vault, |_, _| ());
}

/// Their word proves their build reads the ground (iOS noteGroundCapable) and names what of mine they hold: a first proof is
/// answered with mine, a tag that differs from mine is said again -- once a minute at most.
pub fn heard(vault: &Vault, conv: &str, held: &str) {
    with(vault, |l, s| {
        let mut dirty = false;
        if !s.cap.iter().any(|c| c == conv) {
            s.cap.push(conv.into());
            s.sent.remove(conv);
            dirty = true;
        }
        if held != tag(&mine_of(s)) && s.sent.contains_key(conv) {
            let t = crate::wire::now_ms() / 1000;
            if t - l.healed_at.get(conv).copied().unwrap_or(0) >= 60 {
                l.healed_at.insert(conv.into(), t);
                s.sent.remove(conv);
                dirty = true;
            }
        }
        if dirty {
            save(vault, s);
        }
    });
}

/// The words of my ground due (iOS sendGroundIfNeeded): to every correspondent proven to read it who did not take this one; the
/// picture's content made by `photo` (the media store's bytes of my kept picture).
pub fn due(vault: &Vault, latest: &[String], photo: &dyn Fn(&str) -> Option<Vec<u8>>) -> Vec<(String, String, String)> {
    with(vault, |l, s| {
        let mut g = mine_of(s);
        if let Some(name) = g.strip_prefix("p:").filter(|n| n.starts_with("gnd_")) {
            // my picture rides as it is kept, light; one not light stands as none
            g = match photo(name).filter(|b| is_light(b)) {
                Some(b) => format!("p:{}", crate::wire::b64(&b)),
                None => String::new(),
            };
        }
        let t = tag(&g);
        let word = serde_json::json!({ "g": g, "at": crate::wire::now_ms() as f64 / 1000.0 }).to_string();
        let now = crate::wire::now_ms() / 1000;
        let due: Vec<String> = latest.iter().filter(|c| s.cap.contains(c) && s.sent.get(*c) != Some(&t) && !l.tried_at.get(*c).is_some_and(|(tt, at)| *tt == t && now - at < 60)).cloned().collect();
        for c in &due {
            l.tried_at.insert(c.clone(), (t.clone(), now));
        }
        due.into_iter().map(|c| (c, format!("{MARK}{word}"), t.clone())).collect()
    })
}

/// The network took my ground's letter to them.
pub fn sent(vault: &Vault, conv: &str, t: &str) {
    with(vault, |_, s| {
        s.sent.insert(conv.into(), t.into());
        save(vault, s);
    });
}

/// THEIR GROUND ARRIVED (iOS MTPageGround.note): kept, the latest word winning; an older word changes nothing. A picture is kept in
/// the media store under their chat's name; `keep` lays its bytes there.
pub fn note(vault: &Vault, conv: &str, text: &str, keep: &dyn Fn(&str, &[u8]) -> bool) -> bool {
    let Some(o) = text.strip_prefix(MARK).and_then(|j| serde_json::from_str::<serde_json::Value>(j).ok()) else { return false };
    let g = o["g"].as_str().unwrap_or("").to_string();
    let at = o["at"].as_f64().unwrap_or(0.0);
    with(vault, |_, s| {
        if s.theirs.get(conv).is_some_and(|h| at < h.at) {
            return false;
        }
        let mut t = Theirs { tag: tag(&g), at, ..Default::default() };
        if let Some(n) = g.strip_prefix("n:") {
            if NAMES.contains(&n) {
                t.named = n.into();
            } else if RETIRED.contains(&n) {
                t.named = "default".into();
            }
        } else if let Some(p) = g.strip_prefix("p:") {
            if let Some(b) = crate::wire::unb64(p).filter(|b| b.len() <= LIMIT && b.len() >= 12) {
                let name = format!("pg_{}", crate::wire::hex(&crate::wire::sha(&[b"mt-page-ground\0", conv.as_bytes()])[..12]));
                if keep(&name, &b) {
                    t.photo = name;
                }
            }
        }
        s.theirs.insert(conv.into(), t);
        save(vault, s);
        true
    })
}

/// The ground a correspondent's page wears here.
pub fn theirs(vault: &Vault, conv: &str) -> Option<Theirs> {
    with(vault, |_, s| s.theirs.get(conv).cloned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_ground_rides_to_one_who_reads_it_and_theirs_is_kept_newest_first() {
        let dir = std::env::temp_dir().join(format!("mt-pg-{}", crate::board::fresh_id()));
        let v = Vault::at(&dir).unwrap();
        let none = |_: &str| None;
        // nothing goes before their build is proven; the default is the app's own dark ground (iOS 2304 byDefault)
        assert!(due(&v, &["B".into()], &none).is_empty());
        heard(&v, "B", "0");
        let d = due(&v, &["B".into()], &none);
        assert_eq!((d.len(), d[0].2.as_str()), (1, tag("n:default").as_str()));
        assert!(d[0].1.starts_with(MARK) && d[0].1.contains("\"g\":\"n:default\""));
        sent(&v, "B", &d[0].2);
        assert!(due(&v, &["B".into()], &none).is_empty());
        set_mine(&v, "n:aurora".into());
        assert_eq!(due(&v, &["B".into()], &none)[0].2, tag("n:aurora"));
        // their ground: a drawn one, then an older word changes nothing
        let keep = |_: &str, _: &[u8]| true;
        assert!(note(&v, "B", &format!("{MARK}{{\"g\":\"n:sky\",\"at\":10}}"), &keep));
        assert!(!note(&v, "B", &format!("{MARK}{{\"g\":\"n:rose\",\"at\":5}}"), &keep));
        assert_eq!(theirs(&v, "B").unwrap().named, "sky");
        // the gold told by a build before wears the default ground (iOS 2304 MTWallpaper.retired)
        assert!(note(&v, "C", &format!("{MARK}{{\"g\":\"n:gold\",\"at\":10}}"), &keep));
        assert_eq!(theirs(&v, "C").unwrap().named, "default");
        seat(&v);
        assert_eq!(tail_at(&v.dir().to_string_lossy(), "B"), format!("G{}", tag("n:sky")));
        let _ = std::fs::remove_dir_all(dir);
    }
}
