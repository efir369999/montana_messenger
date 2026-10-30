//! What of the person is not a secret (iOS UserDefaults / @AppStorage: userName, termsAcceptedVersion, cardKind): a small
//! JSON file in the app's local data folder, written whole and atomically. The name a person types loses any crown (iOS
//! MTCrown.plain); a person with no name is called by the call sign the reference picks (iOS MontanaCallsign).

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

/// iOS MontanaSafety.termsVersion.
pub const TERMS_VERSION: i64 = 1;

#[derive(Serialize, Deserialize, Default, Clone, Debug, PartialEq)]
pub struct Settings {
    #[serde(rename = "userName", default)]
    pub user_name: String,
    #[serde(rename = "termsAcceptedVersion", default)]
    pub terms_accepted_version: i64,
    #[serde(rename = "cardKind", default)]
    pub card_kind: String,
    /// the banners (iOS notifEnabled, notifPreview, notifSender): on unless the person turned them off
    #[serde(rename = "notifEnabled", default, skip_serializing_if = "Option::is_none")]
    pub notif_enabled: Option<bool>,
    #[serde(rename = "notifPreview", default, skip_serializing_if = "Option::is_none")]
    pub notif_preview: Option<bool>,
    #[serde(rename = "notifSender", default, skip_serializing_if = "Option::is_none")]
    pub notif_sender: Option<bool>,
    /// iOS notifSound, readReceiptsEnabled, autoDownloadWiFi: on unless turned off
    #[serde(rename = "notifSound", default, skip_serializing_if = "Option::is_none")]
    pub notif_sound: Option<bool>,
    #[serde(rename = "readReceiptsEnabled", default, skip_serializing_if = "Option::is_none")]
    pub read_receipts: Option<bool>,
    /// attachments fetched by themselves over Wi-Fi or a wire (iOS autoDownloadWiFi) -- on unless turned off
    #[serde(rename = "autoDownload", default, skip_serializing_if = "Option::is_none")]
    pub auto_download: Option<bool>,
    /// and over a mobile network -- Windows' WWAN (iOS autoDownloadCellular) -- on unless turned off
    #[serde(rename = "autoDownloadCellular", default, skip_serializing_if = "Option::is_none")]
    pub auto_download_cellular: Option<bool>,
    /// iOS linkPreviewsEnabled: a link I send gets its card, read by this machine from the page -- on unless turned off
    #[serde(rename = "linkPreviewsEnabled", default, skip_serializing_if = "Option::is_none")]
    pub link_previews: Option<bool>,
    /// the fold over objectionable words in their letters (iOS objectionableFilterOn, Guideline 1.2): on unless turned off
    #[serde(rename = "objectionableFilterOn", default, skip_serializing_if = "Option::is_none")]
    pub objectionable_filter: Option<bool>,
    /// iOS presenceSharing: «Online status» -- on unless turned off
    #[serde(rename = "presenceSharing", default, skip_serializing_if = "Option::is_none")]
    pub presence_sharing: Option<bool>,
    /// iOS AppLanguage: "" the system's, "en", "ru"
    #[serde(rename = "AppLanguage", default)]
    pub language: String,
    /// iOS profileBio (140) and profileLink (256): what my correspondents read about me
    #[serde(rename = "profileBio", default)]
    pub bio: String,
    #[serde(rename = "profileLink", default)]
    pub link: String,
}

/// A link as a person types it (iOS MTPeerAbout.url): «site.org» wears https; nothing but the web is a link here -- http or https,
/// the host with a dot, at most 256.
fn url(word: &str) -> Option<String> {
    let t = word.trim();
    if t.is_empty() || t.chars().count() > 256 {
        return None;
    }
    let full = if t.contains("://") { t.to_string() } else { format!("https://{t}") };
    let (scheme, rest) = full.split_once("://")?;
    let host = rest.split(['/', '?', '#']).next().unwrap_or("");
    (["https", "http"].contains(&scheme.to_ascii_lowercase().as_str()) && host.contains('.') && !host.contains(' ')).then_some(full)
}

/// EVERY LINK OF THE FIELD (iOS 2304 MTPeerAbout.links, the author's word 21.10 16:37): a person gives as many links as they type,
/// set apart by spaces or commas; each word is read by the one rule above, the words that are not the web stand aside, a link
/// twice is one, the order stays.
pub fn links(field: &str) -> Vec<String> {
    if field.chars().count() > 256 {
        return vec![];
    }
    let mut out: Vec<String> = vec![];
    for u in field.split(|c: char| c.is_whitespace() || c == ',').filter_map(url) {
        if !out.contains(&u) {
            out.push(u);
        }
    }
    out
}

/// The field as it leaves for the wire and as it is kept of a correspondent (iOS spoken): its links, one space apart.
pub fn kept_link(field: &str) -> String {
    links(field).join(" ")
}

pub struct Profile {
    file: PathBuf,
}

impl Profile {
    pub fn at(dir: &Path) -> Profile {
        let _ = fs::create_dir_all(dir);
        Profile { file: dir.join("settings.json") }
    }

    pub fn read(&self) -> Settings {
        fs::read(&self.file).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
    }

    pub fn write(&self, s: &Settings) -> bool {
        let tmp = self.file.with_extension("tmp");
        serde_json::to_vec_pretty(s).ok().map(|b| fs::write(&tmp, b).is_ok() && fs::rename(&tmp, &self.file).is_ok()) == Some(true)
    }

    /// One change read, made and written whole: two changes at once never lose one another.
    pub fn update(&self, f: impl FnOnce(&mut Settings)) -> bool {
        static ONE: std::sync::Mutex<()> = std::sync::Mutex::new(());
        let _one = ONE.lock().unwrap_or_else(|e| e.into_inner());
        let mut s = self.read();
        f(&mut s);
        self.write(&s)
    }

    /// Everything of the person leaves with the seed (iOS SeedScope).
    pub fn forget(&self) {
        let _ = fs::remove_file(&self.file);
    }
}

/// The crown and its look-alikes: given by a Royal, never typed (iOS MTCrown.plain; Android stripCrown).
const CROWN_MARKS: [u32; 5] = [0x1F451, 0x2654, 0x2655, 0x265A, 0x265B];

pub fn strip_crown(s: &str) -> String {
    if !s.chars().any(|c| CROWN_MARKS.contains(&(c as u32))) {
        return s.to_string(); // a name with no crown stands as typed, its spaces too
    }
    let mut plain = String::new();
    let mut after_mark = false;
    for c in s.chars() {
        let p = c as u32;
        if CROWN_MARKS.contains(&p) {
            after_mark = true;
            continue;
        }
        if after_mark && (p == 0xFE0F || p == 0xFE0E) {
            continue;
        }
        after_mark = false;
        plain.push(c);
    }
    plain.split(' ').filter(|w| !w.is_empty()).collect::<Vec<_>>().join(" ")
}

/// The name as kept: no crown, at most 64 characters (iOS MontanaProfile 684-692).
pub fn kept_name(typed: &str) -> String {
    strip_crown(typed.trim()).chars().take(64).collect()
}

const CALLSIGNS: &str = include_str!("../assets/callsigns.tsv");

struct Row {
    en: &'static str,
    ru: &'static str,
    zh: &'static str,
    emoji: &'static str,
}

fn rows() -> Vec<Row> {
    CALLSIGNS
        .split('\n')
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .filter_map(|l| {
            let f: Vec<&str> = l.trim_end_matches('\r').split('\t').collect();
            (f.len() >= 5).then(|| Row { en: f[1], ru: f[2], zh: f[4], emoji: f.get(5).copied().unwrap_or("") })
        })
        .collect()
}

fn named(r: &Row, lang: &str) -> String {
    let word = if lang.starts_with("ru") { r.ru } else if lang.starts_with("zh") { r.zh } else { r.en };
    if r.emoji.is_empty() { word.to_string() } else { format!("{} {}", r.emoji, word) }
}

/// Every call sign, in the person's language (iOS MontanaCallsign.all): the list a person picks one from.
pub fn callsigns(lang: &str) -> Vec<String> {
    rows().iter().map(|r| named(r, lang)).collect()
}

/// The call sign of a reference (iOS MontanaCallsign.of): sum = sum*31 + byte over the first 8 UTF-8 bytes, UInt32
/// wrapping, the row at sum mod the table's length, read in the person's language.
pub fn callsign_of(reference: &str, lang: &str) -> String {
    let t = rows();
    if t.is_empty() || reference.is_empty() {
        return String::new();
    }
    let mut sum: u32 = 0;
    for b in reference.as_bytes().iter().take(8) {
        sum = sum.wrapping_mul(31).wrapping_add(*b as u32);
    }
    named(&t[(sum % t.len() as u32) as usize], lang)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crowns_never_stand_in_a_name_and_plain_names_stay_as_typed() {
        assert_eq!(strip_crown("Alice  Smith"), "Alice  Smith");
        assert_eq!(strip_crown("👑 Alice"), "Alice");
        assert_eq!(strip_crown("♛\u{FE0F}Bob ♔"), "Bob");
        assert_eq!(kept_name(&"я".repeat(80)).chars().count(), 64);
    }

    #[test]
    fn the_call_sign_is_the_same_fold_as_ios_and_android() {
        let t = rows();
        assert!(t.len() > 100, "the table has {} rows", t.len());
        // the fold by hand for "0123456789abcdef...": 8 bytes '0'..'7'
        let mut sum: u32 = 0;
        for b in b"01234567" {
            sum = sum.wrapping_mul(31).wrapping_add(*b as u32);
        }
        assert_eq!(callsign_of("0123456789abcdef", "en"), named(&t[(sum % t.len() as u32) as usize], "en"));
        assert_ne!(callsign_of("0123456789abcdef", "ru"), callsign_of("0123456789abcdef", "en"));
        assert_eq!(callsign_of("", "ru"), "");
    }

    /// iOS 2304's own vector (MontanaTests.testPageFieldLinks): every link of the field, in its order, none twice; «///» is no link.
    #[test]
    fn every_link_of_the_page_field_as_ios_reads_it() {
        assert_eq!(links("dreamdepartment.io /// montana.xxx"), ["https://dreamdepartment.io", "https://montana.xxx"]);
        assert_eq!(links("montana.xxx, dreamdepartment.io montana.xxx"), ["https://montana.xxx", "https://dreamdepartment.io"]);
        assert_eq!(kept_link("///"), "");
        assert_eq!(kept_link("a.io b.io"), "https://a.io https://b.io", "a correspondent's two links both stand");
        assert_eq!(kept_link("ftp://x.io javascript:alert(1) http://y.org"), "http://y.org");
    }

    #[test]
    fn settings_survive_a_restart_and_leave_with_the_person() {
        let d = std::env::temp_dir().join(format!("montana-profile-{}", std::process::id()));
        let p = Profile::at(&d);
        assert!(p.update(|s| { s.user_name = "Alice".into(); s.terms_accepted_version = TERMS_VERSION; }));
        let again = Profile::at(&d).read();
        assert_eq!((again.user_name.as_str(), again.terms_accepted_version), ("Alice", 1));
        p.forget();
        assert_eq!(Profile::at(&d).read(), Settings::default());
        let _ = fs::remove_dir_all(&d);
    }
}
