//! The doors of the onboarding (iOS MontanaOnboardingView, MontanaSettings.swift 2380-2960; ContentView 438-468), as Tauri
//! commands. The words cross into the window only where the person must read or type them -- the words page right after
//! the birth, the restore field -- and are never kept there; "Copy" copies from this side.

use crate::clipboard;
use crate::profile::{callsign_of, kept_name, Profile, TERMS_VERSION};
use crate::seed::{self, Refused, Seed};
use serde::Serialize;
use std::sync::Mutex;

pub struct Person {
    pub seed: Seed,
    pub profile: Profile,
    /// the language of the person's system, for the call sign
    pub lang: String,
    lock: Mutex<()>,
}

impl Person {
    pub fn new(seed: Seed, profile: Profile, lang: String) -> Person {
        Person { seed, profile, lang, lock: Mutex::new(()) }
    }
}

#[derive(Serialize)]
pub struct State {
    /// a person sits here (iOS MontanaSeed.hasSeed)
    pub seated: bool,
    /// the name shown: the person's, or the call sign
    pub name: String,
    pub callsign: String,
    pub terms_ok: bool,
    /// my face's version (0: none): the window draws it when it changes
    pub face: i64,
}

#[derive(Serialize, Debug)]
#[serde(tag = "kind", content = "count")]
pub enum Failure {
    /// "Exactly 24 words required (entered N)"
    WordCount(usize),
    /// "Invalid phrase. Check the words and their order."
    Invalid,
    /// "The identity could not be stored on this device"
    Storage,
    /// the core refused for a reason of its own
    Core(i32),
}

pub fn state(p: &Person) -> State {
    let s = p.profile.read();
    let callsign = if p.seed.has_seed() { p.seed.twin().map(|t| callsign_of(&t, &p.lang)).unwrap_or_default() } else { String::new() };
    State {
        seated: p.seed.has_seed(),
        name: if s.user_name.is_empty() { callsign.clone() } else { s.user_name },
        callsign,
        terms_ok: s.terms_accepted_version >= TERMS_VERSION,
        face: 0,
    }
}

/// "Create": the core draws the words, they are kept, read back, and handed to the words page once.
pub fn create(p: &Person) -> Result<Vec<String>, Failure> {
    let _g = p.lock.lock().unwrap();
    let words = seed::generate().map_err(|e| match e { Refused::Core(c) => Failure::Core(c), _ => Failure::Invalid })?;
    p.profile.forget();
    p.seed.enter(&words).map_err(|_| Failure::Storage)?;
    let _ = p.seed.twin();
    Ok(words.split(' ').map(str::to_string).collect())
}

/// "Restore": lower case, split on spaces, new lines and commas; exactly 24 words; the core opens keys from them or
/// they are refused (iOS MontanaSettings 2589-2640).
pub fn restore(p: &Person, typed: &str) -> Result<(), Failure> {
    let _g = p.lock.lock().unwrap();
    let words: Vec<String> = typed
        .to_lowercase()
        .split(|c: char| c.is_whitespace() || c == ',')
        .filter(|w| !w.is_empty())
        .map(str::to_string)
        .collect();
    if words.len() != 24 {
        return Err(Failure::WordCount(words.len()));
    }
    match p.seed.enter(&words.join(" ")) {
        Ok(()) => {
            let _ = p.seed.twin();
            Ok(())
        }
        Err(Refused::Storage) => Err(Failure::Storage),
        Err(_) => Err(Failure::Invalid),
    }
}

/// "Copy" on the words page: the stored words onto the clipboard, out of its history and its cloud.
pub fn copy_words(p: &Person) -> bool {
    p.seed.mnemonic().map(|m| clipboard::copy_secret(&m)).unwrap_or(false)
}

/// The name of the profile step: no crown, at most 64; empty is the call sign (iOS ProfileView onboarding Done).
pub fn set_name(p: &Person, typed: &str) -> bool {
    let mut name = kept_name(typed);
    if name.is_empty() {
        name = p.seed.twin().map(|t| callsign_of(&t, &p.lang)).unwrap_or_default();
    }
    p.profile.update(|s| s.user_name = name)
}

pub fn accept_terms(p: &Person) -> bool {
    p.profile.update(|s| s.terms_accepted_version = TERMS_VERSION)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::Vault;

    fn person(name: &str) -> (Person, std::path::PathBuf) {
        let d = std::env::temp_dir().join(format!("montana-person-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        (Person::new(Seed::new(Vault::at(&d.join("vault")).unwrap()), Profile::at(&d), "ru".into()), d)
    }

    #[test]
    fn create_then_name_then_terms_is_the_whole_way_in() {
        let (p, d) = person("way");
        assert!(!state(&p).seated);
        let words = create(&p).unwrap();
        assert_eq!(words.len(), 24);
        let st = state(&p);
        assert!(st.seated && !st.terms_ok && !st.callsign.is_empty() && st.name == st.callsign);
        assert!(set_name(&p, "👑 Алиса"));
        assert_eq!(state(&p).name, "Алиса");
        assert!(accept_terms(&p));
        assert!(state(&p).terms_ok);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn restore_counts_the_words_and_refuses_a_wrong_phrase() {
        let (p, d) = person("restore");
        let words = seed::generate().unwrap();
        assert!(matches!(restore(&p, "one two three"), Err(Failure::WordCount(3))));
        let wrong: Vec<&str> = words.split(' ').map(|w| if w == words.split(' ').next().unwrap() { "zzzz" } else { w }).collect();
        assert!(matches!(restore(&p, &wrong.join(" ")), Err(Failure::Invalid)));
        restore(&p, &words.to_uppercase().replace(' ', ",\n")).unwrap();
        assert_eq!(p.seed.mnemonic().as_deref(), Some(words.as_str()));
        let _ = std::fs::remove_dir_all(&d);
    }
}
