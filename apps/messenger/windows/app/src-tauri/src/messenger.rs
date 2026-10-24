//! THE MESSENGER BEHIND THE WINDOW: the book of correspondences, the card, the postman, and the walk that keeps them moving
//! (iOS MontanaDeliveryEngine's loop; Android's foreground pickup). The window is told when something changed and asks
//! again; it is handed rows to draw, never a secret.

use crate::book::Book;
use crate::card::Card;
use crate::identity::Person;
use crate::meeting::{self, Outcome};
use crate::post::{marks, Desk};
use crate::profile::strip_crown;
use crate::seed;
use crate::vault::Vault;
use serde::Serialize;
use std::sync::Mutex;

pub struct Messenger {
    pub vault: Vault,
    pub book: Book,
    pub media: crate::media::Store,
    /// the faces of correspondents, by chat (sealed like every file here)
    pub faces: crate::media::Store,
    /// a file the person asked for (a tap on a big one): fetched by the next walk whatever its size
    pub want: Mutex<Option<String>>,
    /// the big files the window is handing a stretch at a time (lib.rs chat_big_begin): only their names take pieces
    pub big: Mutex<std::collections::HashSet<String>>,
    /// the twin reference and the author key, derived once per identity
    keys: Mutex<Option<(String, Option<Vec<u8>>)>>,
    /// the chat open in the window (the window says so): no banner rings for it while the window is in front
    pub open: Mutex<Option<String>>,
    pub presence: crate::presence::Presence,
    /// the window in front: (focused, since when, what AP: was said last -- None before any greeting)
    pub front: Mutex<(bool, i64, Option<bool>)>,
    /// the history under the words, opened once per identity (its keys are derived from the words)
    archive: Mutex<Option<crate::history::Archive>>,
    pub dir: std::path::PathBuf,
}

/// A row of the chat list.
#[derive(Serialize)]
pub struct Row {
    #[serde(rename = "ref")]
    pub reference: String,
    pub name: String,
    pub last: String,
    pub at: i64,
    pub mine: bool,
    pub state: i32,
    pub unread: u32,
    pub perm: bool,
    /// their face's version (0: none) -- the window asks face_get when it changes
    pub face: i64,
    pub pinned: bool,
    pub archived: bool,
    pub muted: bool,
    pub marked: bool,
    /// they are here now (typing, in my chat, in the app): the green dot on the face
    pub live: bool,
    pub blocked: bool,
    /// a group's chat at all
    pub group: bool,
    /// what the conversation is to the folders (iOS MTChatFolders.kind): "g" a group, "c" a channel, "" a pair
    pub kind: String,
    /// the last letter is theirs and the filter folds it: the row says «hidden by the filter»
    pub hidden: bool,
    /// the last letter is a shared secret (iOS MTSecretLetter): the row names no title and no content
    pub secret: bool,
    /// my unsent words in this chat (iOS rowModel draft): the row shows «Draft:» and them in place of the last letter
    pub draft: String,
}

/// THE UNSENT WORDS OF EVERY CHAT (iOS ChatStore.draftsAll / setDraft, «draftsMap»): one map sealed in the device-only vault,
/// the chat's name inside the seal, never said to anyone -- the words belong to this computer's field, as iOS keeps them
const DRAFTS: &str = "draftsMap";
static DRAFTS_LOCK: Mutex<()> = Mutex::new(());

/// The words a letter shows, for the filter: a file's caption, else the letter itself.
fn words_of(text: &str) -> String {
    match text.strip_prefix(crate::media::MARK) {
        Some(j) => serde_json::from_str::<serde_json::Value>(j).ok().and_then(|m| m["cap"].as_str().map(str::to_string)).unwrap_or_default(),
        None => text.to_string(),
    }
}

/// A letter as the conversation draws it.
#[derive(Serialize)]
pub struct Letter {
    pub mid: String,
    pub text: String,
    pub mine: bool,
    pub at: i64,
    pub state: i32,
    pub qt: String,
    pub qm: String,
    pub edited: bool,
    pub my_react: String,
    pub peer_react: String,
    /// in a group: the speaker's name and seat (for the name over a run of bubbles and its tint); an event row says what
    /// happened in `text` and is drawn in the middle
    pub speaker: String,
    pub seat: String,
    pub event: bool,
    /// a file's letter: its file is here / is gone from every store
    pub file: bool,
    pub gone: bool,
    /// a channel's post: how many people saw it (iOS MTChannelViews; 0 -- no channel's post); its writer's name where the
    /// channel signs its posts
    pub views: u32,
    pub sign: String,
    /// the card of a link the letter carries, as JSON (iOS MTLinkPreview); empty -- none
    pub lp: String,
    /// a channel's post where the channel takes comments: how many stand under it; -1 -- no comments here
    pub comments: i32,
    /// theirs, and the filter folds it until the person's tap (iOS filterFolds)
    pub hidden: bool,
    /// a shared secret (iOS MTSecretLetter): only its title is drawn, never its machine line
    pub secret: bool,
    /// the letter's seal head and gematria (iOS MTLetterSeal); empty and 0 -- a row without a wire name
    pub seal: String,
    pub gem: i64,
}

#[derive(Serialize)]
pub struct Talk {
    #[serde(rename = "ref")]
    pub reference: String,
    pub name: String,
    /// its sound is off (a channel's subscriber turns it here, iOS MTChannelSubscriberBar)
    pub muted: bool,
    pub perm: bool,
    pub unread: u32,
    pub face: i64,
    pub blocked: bool,
    /// the pinned letters still in the feed, newest last
    pub pins: Vec<String>,
    /// a group's own: how many, whether I own it, whether I am out
    pub group: Option<serde_json::Value>,
    pub msgs: Vec<Letter>,
}

impl Messenger {
    pub fn new(vault: Vault, media: crate::media::Store, faces: crate::media::Store, dir: std::path::PathBuf) -> Messenger {
        Messenger { book: Book::new(vault.clone()), vault, media, faces, want: Mutex::new(None), big: Default::default(), keys: Mutex::new(None), open: Mutex::new(None),
                    presence: Default::default(), front: Mutex::new((true, crate::wire::now_ms(), None)),
                    archive: Mutex::new(None), dir }
    }

    fn keys(&self, p: &Person) -> Option<(String, Option<Vec<u8>>)> {
        let mut g = self.keys.lock().unwrap();
        if g.is_none() {
            let words = p.seed.mnemonic()?;
            *g = Some((p.seed.twin()?, seed::author_key_of(&words)));
        }
        g.clone()
    }

    /// The postman of this person; None before the person sits here and agrees to the terms.
    pub fn desk<'a>(&'a self, p: &Person) -> Option<Desk<'a>> {
        let s = p.profile.read();
        if s.terms_accepted_version < crate::profile::TERMS_VERSION {
            return None;
        }
        let (twin, author_key) = self.keys(p)?;
        Some(Desk { vault: &self.vault, book: &self.book, twin, author_key, my_name: strip_crown(s.user_name.trim()), news: Default::default(), media: &self.media, faces: &self.faces,
                    self_face: self.self_face().unwrap_or_default(), about: (s.bio.clone(), s.link.clone()),
                    read_receipts: s.read_receipts != Some(false), presence: &self.presence, archive: self.archive(p) })
    }

    /// My face (iOS MTSelfFace): a square JPEG kept in the vault; None when I show none.
    pub fn self_face(&self) -> Option<Vec<u8>> {
        self.vault.get("selfFace").filter(|f| !f.is_empty())
    }

    /// My face changed (or left): kept, and every correspondent and my card will hear it.
    pub fn set_self_face(&self, face: Option<&[u8]>) -> bool {
        let ok = match face {
            Some(f) => self.vault.set("selfFace", f),
            None => { self.vault.delete("selfFace"); true }
        };
        self.vault.delete("cardFaceUp");
        ok
    }

    /// THE FACE BESIDE MY CARD (iOS uploadFace): the one who opens my link sees it at once; laid again when it changed or
    /// five days passed. Off the caller's thread.
    pub fn lay_card_face(&self, link: &str) {
        let Some(inv) = meeting::invite(link) else { return };
        let face = self.self_face().unwrap_or_default();
        let stamp = format!("{}:{}", crate::post::face_tag(&face), crate::wire::b64url(&inv));
        let now = crate::wire::now_ms() / 1000;
        let last = self.vault.get("cardFaceUp").and_then(|b| String::from_utf8(b).ok()).unwrap_or_default();
        if let Some((s, at)) = last.rsplit_once('|') {
            if s == stamp && now - at.parse::<i64>().unwrap_or(0) < 5 * 86_400 {
                return;
            }
        }
        if last.is_empty() && face.is_empty() {
            return; // nothing lay beside the card, nothing to clear
        }
        let Some(sealed) = crate::crypto::seal(&crate::wire::domained("mt-rdv-fk", &[&inv]), &face) else { return };
        let bid = crate::wire::hex(&crate::wire::domained("mt-rdv-f", &[&inv]));
        let v = self.vault.clone();
        std::thread::spawn(move || {
            if crate::doors::put_blob(&bid, &sealed) {
                v.set("cardFaceUp", format!("{stamp}|{now}").as_bytes());
            }
        });
    }

    /// A new person sits here: what the last one derived leaves.
    pub fn reseat(&self) {
        *self.keys.lock().unwrap() = None;
        *self.archive.lock().unwrap() = None;
    }

    /// THE ARCHIVE OF THIS IDENTITY (<data>/archive), its keys from the words, this machine's own device id (16 bytes, kept).
    pub fn archive(&self, p: &Person) -> Option<crate::history::Archive> {
        let mut g = self.archive.lock().unwrap();
        if g.is_none() {
            let words = p.seed.mnemonic()?;
            let device: [u8; 16] = match self.vault.get("deviceId").filter(|d| d.len() == 16) {
                Some(d) => d.try_into().ok()?,
                None => {
                    let d = crate::crypto::random(16)?;
                    if !self.vault.set("deviceId", &d) {
                        return None;
                    }
                    d.try_into().ok()?
                }
            };
            *g = Some(crate::history::Archive::new(&self.dir.join("archive"), crate::history::keys(&words)?, device));
        }
        g.clone()
    }

    /// The letters this machine held before it kept an archive go into it once (iOS: the archive mirrors the feed).
    pub fn fill_archive(&self, p: &Person) {
        let Some(d) = self.desk(p) else { return };
        let Some(a) = d.archive.as_ref() else { return };
        // THE FACES SEALED BESIDE THE LETTERS (iOS ChatStore's sealFace pass): every correspondent's face this archive does not
        // hold yet is put there, so the copy made now carries it
        for c in self.book.all().into_iter().filter(|c| !crate::groups::is_group(&c.reference)) {
            if let Some(face) = self.faces.get(&c.reference).filter(|f| !f.is_empty()) {
                let folder = crate::history::label(&a.keys().hk, &c.reference);
                if a.get_media(&folder, crate::history::FACE_BLOB).as_deref() != Some(face.as_slice()) {
                    a.put_media(&c.reference, crate::history::FACE_BLOB, &face);
                }
            }
        }
        if self.vault.has("archiveFilled") {
            return;
        }
        for c in self.book.all() {
            for m in c.msgs.iter().filter(|m| marks::is_row(&m.text) && !m.mid.starts_with("arc:")) {
                d.archive_row(&c.reference, m.mine, m.at, &m.mid, &m.text);
            }
        }
        self.vault.set("archiveFilled", b"1");
    }

    /// The name a chat shows (iOS MTNameBook.display): mine for them, else the one they gave; an empty one the window calls
    /// «Correspondent».
    fn shown_of(&self, c: &crate::book::Chat) -> String {
        if c.alias.trim().is_empty() { c.name.trim().to_string() } else { c.alias.trim().to_string() }
    }

    pub fn drafts(&self) -> std::collections::BTreeMap<String, String> {
        self.vault.get(DRAFTS).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
    }

    /// The field's words kept for a chat at every change (iOS persistDraft); an empty field takes its draft away. False when the
    /// vault refused the write.
    pub fn keep_draft(&self, chat: &str, text: &str) -> bool {
        let _one = DRAFTS_LOCK.lock().unwrap();
        let mut map = self.drafts();
        if map.get(chat).map(String::as_str).unwrap_or("") == text {
            return true;   // the disk already says what the field says
        }
        if text.is_empty() {
            map.remove(chat);
        } else {
            map.insert(chat.to_string(), text.chars().take(4500).collect());
        }
        self.vault.set(DRAFTS, &serde_json::to_vec(&map).unwrap_or_default())
    }

    pub fn rows(&self) -> Vec<Row> {
        let held = crate::groups::held_of(&self.vault);
        let drafts = self.drafts();
        let mut rows: Vec<Row> = self
            .book
            .all()
            .into_iter()
            .filter(|c| crate::book::is_saved(&c.reference) || ((self.book.secret(&c.reference).is_some() || crate::groups::is_group(&c.reference)) && !c.hidden))
            .map(|c| {
                // a game's step is the board's; the Money Flow's own row stands in the list as itself (iOS MTRowLetter.preview)
                let last = c.msgs.iter().rev().find(|m| (marks::is_row(&m.text) && !crate::chess::is_step(&m.text)) || m.text == marks::FLOW_ROW);
                Row {
                    name: self.shown_of(&c),
                    last: last.map(|m| if crate::passwords::is_letter(&m.text) { crate::passwords::shown(&m.text) } else { m.text.clone() }).unwrap_or_default(),
                    at: last.map(|m| m.at).unwrap_or(0),
                    mine: last.is_some_and(|m| m.mine),
                    state: last.map(|m| m.state).unwrap_or(0),
                    unread: c.unread,
                    perm: c.perm,
                    face: if self.faces.has(&c.reference) { c.face_at.max(1) } else { 0 },
                    pinned: c.pinned_at > 0,
                    archived: c.archived,
                    muted: c.muted,
                    marked: c.marked,
                    live: !c.blocked && self.presence.live(&c.reference),
                    blocked: c.blocked,
                    group: crate::groups::is_group(&c.reference),
                    kind: c.reference.strip_prefix("grp:").and_then(|id| held.get(id)).map(|g| g.kind.clone()).unwrap_or_default(),
                    hidden: last.is_some_and(|m| crate::filter::folds(m.mine, &words_of(&m.text))),
                    secret: last.is_some_and(|m| crate::passwords::is_letter(&m.text)),
                    draft: drafts.get(&c.reference).cloned().unwrap_or_default(),
                    reference: c.reference,
                }
            })
            .collect();
        // SAVED MESSAGES IS ALWAYS IN THE LIST (iOS listRows), its room born in the book only when it is opened or written to
        if !rows.iter().any(|r| crate::book::is_saved(&r.reference)) {
            rows.push(Row {
                reference: crate::book::SAVED.into(), name: crate::book::SAVED.into(), last: String::new(), at: 0, mine: false, state: 0,
                unread: 0, perm: true, face: 0, pinned: false, archived: false, muted: false, marked: false, live: false, blocked: false,
                group: false, kind: String::new(), hidden: false, secret: false,
                draft: drafts.get(crate::book::SAVED).cloned().unwrap_or_default(),
            });
        }
        // THE ONE ORDER (iOS ChatStore.listOrder): the pinned first; then the moment of the chat's newest event -- its newest
        // letter's birth (iOS bump: the birth, not the moment this computer handled it) or the moment the person pinned it --
        // the freshest above; then by name
        let order: std::collections::HashMap<String, (bool, i64)> = self
            .book
            .all()
            .into_iter()
            .map(|c| {
                let newest = c.msgs.iter().map(|m| m.at).max().unwrap_or(0);
                (c.reference, (c.pinned_at > 0, newest.max(c.ordered_at)))
            })
            .collect();
        rows.sort_by(|a, b| {
            let (pa, oa) = order.get(&a.reference).copied().unwrap_or_default();
            let (pb, ob) = order.get(&b.reference).copied().unwrap_or_default();
            list_order((pa, oa, &a.name), (pb, ob, &b.name))
        });
        rows
    }

    /// One conversation as the window draws it; `me` -- my name, the signature under a channel's posts of mine.
    pub fn talk(&self, r: &str, me: &str) -> Option<Talk> {
        let c = self.book.chat(r)?;
        let group = r.strip_prefix("grp:").and_then(|id| crate::groups::held_of(&self.vault).remove(id));
        let ru = self.vault.get("lang").is_none_or(|l| l != b"en");
        let gone: Vec<String> = self.vault.get("mediaGone").and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
            .and_then(|v| v.as_object().map(|o| o.keys().cloned().collect())).unwrap_or_default();
        let channel = group.as_ref().filter(|g| g.kind == "c");
        let views = channel.map(|g| crate::groups::views_of(&self.vault, r, g.owner.is_empty())).unwrap_or_default();
        let talks = channel.filter(|g| g.talks).map(|_| crate::groups::comments_of(&self.vault, r));
        let my_name = strip_crown(me.trim());
        Some(Talk {
            name: self.shown_of(&c),
            unread: c.unread,
            muted: c.muted,
            face: if self.faces.has(r) { c.face_at.max(1) } else { 0 },
            blocked: c.blocked,
            pins: c.pins.iter().filter(|p| c.msgs.iter().any(|m| &m.mid == *p)).cloned().collect(),
            group: group.as_ref().map(|g| serde_json::json!({ "count": g.count, "owner": g.owner.is_empty(), "left": g.left, "removed": g.removed,
                                                               "kind": g.kind, "me": g.me, "signs": g.signs, "reacts": !g.reacts_off,
                                                               "talks": g.talks, "react_list": g.react_list, "admin": g.admins.contains(&g.me),
                                                               "rooms": crate::rooms::kinds(g),
                                                               "rights": crate::groups::ADMIN_RIGHTS.iter().filter(|r| crate::groups::admin_can(g, &g.me, r)).collect::<Vec<_>>() })),
            perm: c.perm,
            msgs: c
                .msgs
                .into_iter()
                .filter(|m| (marks::is_row(&m.text) && !crate::chess::is_step(&m.text)) || m.text.starts_with(crate::groups::EVENT) || m.text.starts_with(crate::calls::LOG)
                            || m.text == marks::FLOW_ROW)
                .map(|m| {
                    let media = m.text.starts_with(crate::media::MARK);
                    let seat = m.from.rsplit('/').next().unwrap_or("").to_string();
                    let speaker = group.as_ref().filter(|_| !seat.is_empty())
                        .map(|g| g.names.get(&seat).cloned().filter(|n| !n.is_empty()).unwrap_or_else(|| if ru { "Участник".into() } else { "Member".into() }))
                        .unwrap_or_default();
                    let call = m.text.starts_with(crate::calls::LOG);
                    let event = m.text.starts_with(crate::groups::EVENT) || call;
                    let text = if call { call_words(&m.text[crate::calls::LOG.len()..], ru) } else { match (&group, event) {
                        (Some(g), true) => serde_json::from_str::<serde_json::Value>(&m.text[crate::groups::EVENT.len()..]).ok()
                            .map(|e| crate::groups::event_words(&e, &g.names, &g.me, ru)).unwrap_or_default(),
                        _ => m.text.clone(),
                    } };
                    let m = crate::book::Msg { text, ..m };
                    let post = channel.is_some() && !event;
                    let sign = match channel.filter(|g| post && g.signs) {
                        Some(_) if m.mine => my_name.clone(),
                        Some(_) => speaker.clone(),
                        None => String::new(),
                    };
                    let hidden = !event && crate::filter::folds(m.mine, &words_of(&m.text));
                    let secret = !event && crate::passwords::is_letter(&m.text);
                    let m = if secret { crate::book::Msg { text: crate::passwords::shown(&m.text), ..m } } else { m };
                    let (seal, gem) = if event { None } else { crate::board::letter_mark(&m.mid) }.unwrap_or_default();
                    Letter { seal, gem, file: media && self.media.has(&m.mid), gone: media && gone.contains(&m.mid), speaker, seat, event, hidden, secret,
                             views: if post { views.get(&m.mid).copied().unwrap_or(1).max(1) } else { 0 }, sign, lp: m.lp,
                             comments: match (&talks, post) { (Some(t), true) => t.get(&m.mid).map_or(0, |l| l.len() as i32), _ => -1 },
                             mid: m.mid, text: m.text,
                             mine: m.mine, at: m.at, state: m.state, qt: m.qt, qm: m.qm, edited: m.edited, my_react: m.my_react,
                             peer_react: m.peer_react }
                })
                .collect(),
            reference: c.reference,
        })
    }

    /// When the link of the day renews (ms).
    pub fn renews(&self) -> i64 {
        (Card { vault: &self.vault }).short_renews().unwrap_or(0)
    }

    /// The person's link of the kind chosen («permanent» unless «temporary» was picked; iOS cardKind).
    pub fn card_link(&self, p: &Person, kind: &str) -> Option<String> {
        let name = strip_crown(p.profile.read().user_name.trim());
        let card = Card { vault: &self.vault };
        let link = if kind == "temporary" { card.offer_short(&name) } else { card.offer_permanent(&name) };
        if let Some(d) = self.desk(p) {
            d.twin_cards(); // the live cards ride to the person's other devices: an introduction by them opens there too (iOS)
        }
        link
    }

    /// A link met: the chat stands; the face beside the card is read, and mine is laid beside the new pipe (iOS meet).
    pub fn meet(&self, link: &str) -> Outcome {
        let out = meeting::meet(&self.vault, &self.book, link);
        if let (Outcome::Opened(r), Some(inv)) = (&out, meeting::invite(link)) {
            let fresh = self.book.chat(r).is_some_and(|c| c.face_at == 0);
            if fresh {
                if let Some(face) = crate::doors::get_blob(&crate::wire::hex(&crate::wire::domained("mt-rdv-f", &[&inv])))
                    .and_then(|s| crate::crypto::open(&crate::wire::domained("mt-rdv-fk", &[&inv]), &s))
                    .filter(|f| !f.is_empty() && f.len() <= 262_144)
                {
                    if self.faces.put(r, &face) {
                        self.book.edit(r, |c| c.face_at = 1);
                    }
                }
                if let Some(secret) = self.book.secret(r) {
                    let face = self.self_face().unwrap_or_default();
                    if let Some(sealed) = crate::crypto::seal(&crate::post::pipe_face_key(&secret), &face) {
                        crate::doors::put_blob(&crate::post::pipe_face_bid(&secret), &sealed);
                    }
                }
            }
        }
        out
    }

    /// THE FILES OF EVERY CONVERSATION (iOS Gallery and Music): each letter with a file, newest last, with its chat and name.
    pub fn files(&self) -> Vec<serde_json::Value> {
        let mut out = vec![];
        for c in self.book.all().into_iter().filter(|c| !c.hidden) {
            for m in c.msgs.iter().filter(|m| m.text.starts_with(crate::media::MARK)) {
                let manifest: serde_json::Value = serde_json::from_str(&m.text[crate::media::MARK.len()..]).unwrap_or_default();
                out.push(serde_json::json!({ "chat": c.reference, "name": self.shown_of(&c), "mid": m.mid, "at": m.at, "mine": m.mine,
                                             "file": self.media.has(&m.mid), "m": manifest }));
            }
        }
        out.sort_by_key(|v| v["at"].as_i64().unwrap_or(0));
        out
    }

    /// One of the person's own marks on a chat: pinned (five at most, iOS pinnedChats), archived, muted, marked unread; «read»
    /// clears the count here and says nothing (iOS markRead tellPeer: false).
    pub fn flag(&self, r: &str, flag: &str, on: bool) -> bool {
        if crate::book::is_saved(r) && self.book.chat(r).is_none() {
            self.book.edit(r, |_| {});   // Saved Messages stands in the list before its room is born: a mark on it bears it
        }
        if self.book.chat(r).is_none() {
            return false;
        }
        if flag == "pin" && on && self.book.all().iter().filter(|c| c.pinned_at > 0 && c.reference != r).count() >= 5 {
            return false; // a sixth pin is refused, as on iOS
        }
        self.book.edit(r, |c| match flag {
            "pin" => {
                c.pinned_at = if on { crate::wire::now_ms() } else { 0 };
                c.ordered_at = c.ordered_at.max(c.pinned_at);
            }
            "archive" => {
                c.archived = on;
                if on {
                    c.pinned_at = 0;
                }
            }
            "mute" => c.muted = on,
            "unread" => {
                c.marked = on;
                if !on {
                    c.unread = 0;
                }
            }
            _ => {}
        });
        true
    }

    /// Whether a chat says nothing when a letter lands (iOS MTQuietChats: muted or archived).
    pub fn quiet(&self, r: &str) -> bool {
        self.book.chat(r).is_some_and(|c| c.muted || c.archived)
    }

    /// THE SEARCH OF LETTERS (iOS: the chats' search finds letters too): the newest hundred whose words (a file's name or
    /// caption) hold what was typed.
    pub fn search(&self, q: &str) -> Vec<serde_json::Value> {
        let q = q.trim().to_lowercase();
        if q.chars().count() < 2 {
            return vec![];
        }
        let mut out = vec![];
        for c in self.book.all().into_iter().filter(|c| !c.hidden && !c.blocked) {
            for m in c.msgs.iter().filter(|m| marks::is_row(&m.text)) {
                let words = if let Some(j) = m.text.strip_prefix(crate::media::MARK) {
                    let o: serde_json::Value = serde_json::from_str(j).unwrap_or_default();
                    format!("{} {}", o["n"].as_str().unwrap_or(""), o["cap"].as_str().unwrap_or(""))
                } else {
                    m.text.clone()
                };
                if words.to_lowercase().contains(&q) {
                    out.push(serde_json::json!({ "chat": c.reference, "name": self.shown_of(&c), "mid": m.mid, "text": words.trim(),
                                                 "at": m.at, "mine": m.mine, "face": if self.faces.has(&c.reference) { c.face_at.max(1) } else { 0 } }));
                }
            }
        }
        out.sort_by_key(|v| std::cmp::Reverse(v["at"].as_i64().unwrap_or(0)));
        out.truncate(100);
        out
    }

    /// THE CALLS' LOG (iOS CallsTabView): every call row of every chat, newest first; a row is named by its chat and its letter
    /// (iOS CallRecord.id), and leaves by the letter's own «delete for me» (iOS deleteCallLog: dropRows).
    pub fn calls_log(&self) -> Vec<serde_json::Value> {
        let mut out = vec![];
        for c in self.book.all().into_iter().filter(|c| !c.hidden && !crate::groups::is_group(&c.reference)) {
            for m in c.msgs.iter().filter(|m| m.text.starts_with(crate::calls::LOG)) {
                let o: serde_json::Value = serde_json::from_str(&m.text[crate::calls::LOG.len()..]).unwrap_or_default();
                out.push(serde_json::json!({ "chat": c.reference, "mid": m.mid, "name": self.shown_of(&c), "blocked": c.blocked, "at": m.at, "v": o["v"], "inc": o["inc"], "dur": o["dur"],
                                             "miss": o["miss"], "face": if self.faces.has(&c.reference) { c.face_at.max(1) } else { 0 } }));
            }
        }
        out.sort_by_key(|v| std::cmp::Reverse(v["at"].as_i64().unwrap_or(0)));
        out
    }

    /// THE MISSED CALLS NOT YET SEEN (iOS missedCallsUnseen): the incoming missed rows of the log newer than the moment the calls
    /// page was last looked at -- that moment in the vault («callsSeenAt», seconds, as iOS keeps it); the first count takes the
    /// past as seen, so the history's old misses never stand as news.
    pub fn calls_missed(&self) -> usize {
        let seen = self.vault.get("callsSeenAt").and_then(|b| String::from_utf8(b).ok()).and_then(|s| s.parse::<f64>().ok());
        let Some(seen) = seen else {
            self.vault.set("callsSeenAt", (crate::wire::now_ms() as f64 / 1000.0).to_string().as_bytes());
            return 0;
        };
        missed_since(&self.calls_log(), seen)
    }

    /// The calls page looked at (iOS clearMissedCallsBadge): what was missed is seen.
    pub fn calls_seen(&self) {
        if self.calls_missed() > 0 {
            self.vault.set("callsSeenAt", (crate::wire::now_ms() as f64 / 1000.0).to_string().as_bytes());
        }
    }

    /// Their words about themselves, for their page: the name shown, their words, their link, my name for them and theirs.
    pub fn peer(&self, r: &str) -> Option<(String, String, String, String, String)> {
        self.book.chat(r).map(|c| (self.shown_of(&c), c.peer_bio.clone(), c.peer_link.clone(), c.alias.clone(), c.name.trim().to_string()))
    }

    /// MY NAME FOR THEM (iOS MTNameBook.setManual): the first name and the last; a name equal to their own clears mine, as an
    /// empty one does -- their word shows again, and every rename of theirs with it.
    pub fn rename(&self, r: &str, first: &str, last: &str) -> bool {
        let Some(c) = self.book.chat(r).filter(|_| !crate::groups::is_group(r)) else { return false };
        let alias = alias_of(first, last, &c.name);
        self.book.edit(r, |c| c.alias = alias);
        true
    }
}

/// The log's incoming missed rows newer than `seen` (seconds; a row's moment is in milliseconds) -- iOS missedCallsUnseen's filter.
pub fn missed_since(log: &[serde_json::Value], seen: f64) -> usize {
    log.iter().filter(|r| r["inc"] == true && r["miss"] == true && r["at"].as_f64().unwrap_or(0.0) / 1000.0 > seen).count()
}

/// My name for a correspondent out of its two fields (iOS setManual): trimmed, sixty-four signs at most, and none when it is
/// theirs.
pub fn alias_of(first: &str, last: &str, theirs: &str) -> String {
    let full = format!("{} {}", first.trim(), last.trim()).trim().chars().take(64).collect::<String>();
    if full == theirs.trim() { String::new() } else { full }
}

/// A call's row in words (iOS ContentView 2930-2934): voice or video; missed -- «Missed» (theirs) or «No answer» (mine); talked
/// -- its length; else «The connection failed».
fn call_words(j: &str, ru: bool) -> String {
    let o: serde_json::Value = serde_json::from_str(j).unwrap_or_default();
    let video = o["v"].as_bool().unwrap_or(false);
    let inc = o["inc"].as_bool().unwrap_or(false);
    let dur = o["dur"].as_i64().unwrap_or(0);
    let kind = match (video, ru) { (true, true) => "📹 Видеозвонок", (false, true) => "📞 Аудиозвонок", (true, false) => "📹 Video call", (false, false) => "📞 Voice call" };
    let state = if o["miss"].as_bool().unwrap_or(false) {
        match (inc, ru) { (true, true) => "Пропущенный".to_string(), (false, true) => "Нет ответа".to_string(), (true, false) => "Missed".to_string(), (false, false) => "No answer".to_string() }
    } else if dur > 0 {
        format!("{}:{:02}", dur / 60, dur % 60)
    } else if ru { "Соединение не удалось".to_string() } else { "The connection failed".to_string() };
    format!("{kind} · {state}")
}

/// iOS ChatStore.listOrder over (pinned, the chat's moment, its name): the pinned first, the freshest moment above, then the name
fn list_order(a: (bool, i64, &str), b: (bool, i64, &str)) -> std::cmp::Ordering {
    b.0.cmp(&a.0).then(b.1.cmp(&a.1)).then_with(|| a.2.cmp(b.2))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_list_stands_as_ios_orders_it() {
        let mut rows = [(false, 50, "Вера"), (true, 10, "Анна"), (true, 30, "Борис"), (false, 50, "Глеб"), (false, 90, "Дина")];
        rows.sort_by(|a, b| list_order(*a, *b));
        let names: Vec<&str> = rows.iter().map(|r| r.2).collect();
        assert_eq!(names, ["Борис", "Анна", "Дина", "Вера", "Глеб"], "the one pinned last on top, then the freshest, then the name");
    }

    #[test]
    fn my_name_for_them_stands_over_theirs_and_theirs_clears_it() {
        assert_eq!(alias_of(" Боря ", "", "Борис Тест"), "Боря");
        assert_eq!(alias_of("Борис", "Петров", "Борис Тест"), "Борис Петров");
        assert_eq!(alias_of("Борис", "Тест", "Борис Тест"), "", "their own word is no name of mine");
        assert_eq!(alias_of("", " ", "Борис Тест"), "", "an empty one gives theirs back");
        assert_eq!(alias_of(&"я".repeat(80), "", "").chars().count(), 64);
    }

    #[test]
    fn only_their_missed_calls_after_the_page_was_seen_are_news() {
        let row = |inc: bool, miss: bool, at: i64| serde_json::json!({ "inc": inc, "miss": miss, "at": at });
        let log = [row(true, true, 1_000_000), row(true, true, 3_000_000), row(false, true, 3_000_000), row(true, false, 3_000_000)];
        assert_eq!(missed_since(&log, 2_000.0), 1, "their missed call after the look; my unanswered one and a talk are no news");
        assert_eq!(missed_since(&log, 0.0), 2);
        assert_eq!(missed_since(&log, 3_000.0), 0, "seen at its very moment");
    }
}
