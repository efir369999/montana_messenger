//! THE WALL (iOS MTBoard, MontanaBoard.swift -- «Board» in the code, «Wall» on the screen): on a person's page the people they
//! allow write posts -- words and pictures with their captions -- and a post lives with those who keep it. The words travel as
//! the service word «WL:» in the one pipe between two people, the files as sealed pieces on the node's blind store under keys
//! that ride only inside the pipes. The wall's owner answers for their wall: a post is sent to them, its counts are kept by them,
//! and the owner carries the page to each correspondent whose build speaks the wall when its version moves; a visitor asks for it
//! when the version their presence word names differs from the page held. A visitor never learns who the other visitors are.
//! Coins on posts and comments are the book's (iOS MTBoardCoins, TimeCoin allowed by the owner's word of 21.10.2026): a gift on a
//! post is paid first and carried by «coin»; a comment costs one coin to the wall's owner, four of five burn, the fifth goes to the
//! post's writer by «cpay».

use crate::presence::wire_tag;
use crate::vault::Vault;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

pub const MARK: &str = "\u{200B}\u{200B}WL:";
const KEY: &str = "board";
pub const PAGE_SIZE: usize = 30;
const COMMENTS_SHOWN: usize = 20;
const COMMENTS_KEPT: usize = 200;
const TEXT_LIMIT: usize = 4000;
const COMMENT_LIMIT: usize = 1000;
const MEDIA_LIMIT: usize = 10;
const POSTS_PER_WRITER: usize = 100;
const WALL_LIMIT: usize = 500;
const WALLS: usize = 64;
const THUMB_LIMIT: usize = 60_000;
const FACE_LIMIT: usize = 16_000;
const PUSH_TO: usize = 128;
const VIEWED_KEPT: usize = 4000;
/// The page's shape is part of its version (iOS pageShape «c4»: a page carries its posts' views).
const PAGE_SHAPE: &str = "c4";
pub const ZERO: &str = "0000000000000000000000000000000000000000000000000000000000000000";
const ANSWER_S: i64 = 30;
const ASK_S: i64 = 60;
const LOOK_STALE_S: f64 = 600.0;

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Chunk {
    #[serde(default)]
    pub bid: String,
    #[serde(default)]
    pub cs: i64,
}

/// A picture's frame in its post (iOS MTBoardFrame): the tile's shape and the part of the picture it shows.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Frame {
    pub a: f64,
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

/// One file of a post (iOS MTBoardMedia): what a keeper needs to fetch it, and what a page needs to draw it before.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Media {
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub ext: String,
    #[serde(default)]
    pub size: i64,
    #[serde(default)]
    pub key: String,
    #[serde(default)]
    pub chunks: Vec<Chunk>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub thumb: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub dur: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub fr: Option<Frame>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Comment {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub by: String,
    #[serde(default)]
    pub glyph: String,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub at: f64,
    /// who wrote it, on the wall owner's machine only -- never on a page ("" the owner)
    #[serde(rename = "ref", skip_serializing_if = "Option::is_none", default)]
    pub reference: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub fc: Option<String>,
    /// on a page: written by the visitor it is carried to
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub m: Option<bool>,
    /// on a page: written by the wall's owner
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub o: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub h: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub pv: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub hid: Option<bool>,
}

/// A FILE OF A POST BEING WRITTEN, KEPT ON THIS MACHINE (iOS MTBoardDraftFile): the media store's name it was taken under the moment
/// it was picked, with what the post shows of it -- its size, a track's or a film's length, a picture's poster and frame.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct DraftFile {
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub ext: String,
    #[serde(default)]
    pub size: i64,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub thumb: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub dur: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub fr: Option<Frame>,
}

/// A POST NOT YET PUBLISHED (iOS MTBoardDraft, the author's word 25.09: «the wall keeps even a draft not published -- against
/// failures, the network and every other turn»): its words, its files and the moment it was begun, one a wall.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Draft {
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub files: Vec<DraftFile>,
    #[serde(default)]
    pub at: f64,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub lp: Option<String>,
}

/// A post as its wall's owner keeps it (iOS MTBoardPost): the references never leave the owner's machine.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Post {
    pub id: String,
    /// the writer's reference on the owner's machine; "" -- the owner
    #[serde(default)]
    pub author: String,
    #[serde(rename = "byName", default)]
    pub by_name: String,
    #[serde(rename = "byGlyph", default)]
    pub by_glyph: String,
    #[serde(default)]
    pub at: f64,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub media: Vec<Media>,
    #[serde(default)]
    pub pinned: bool,
    #[serde(default)]
    pub keepers: Vec<String>,
    #[serde(default)]
    pub likes: Vec<String>,
    #[serde(default)]
    pub downloads: Vec<String>,
    #[serde(default)]
    pub reposts: Vec<String>,
    #[serde(default)]
    pub comments: Vec<Comment>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub from: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub face: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub ed: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub lp: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub n: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub views: Option<Vec<String>>,
    /// the coins its comments brought (iOS cc): every fifth goes to its writer
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub cc: Option<i64>,
    /// a repost: the wall it was taken from, by reference on this machine -- never on a page (iOS src)
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub src: Option<String>,
    /// a repost: its writer by reference when this machine knows them, "" -- I wrote it; never on a page (iOS srcBy)
    #[serde(rename = "srcBy", skip_serializing_if = "Option::is_none", default)]
    pub src_by: Option<String>,
}

/// A post as a visitor sees it (iOS MTBoardSeen): the counts and the visitor's own marks, nobody's reference.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Seen {
    #[serde(default)]
    pub id: String,
    #[serde(rename = "byName", default)]
    pub by_name: String,
    #[serde(rename = "byGlyph", default)]
    pub by_glyph: String,
    #[serde(default)]
    pub at: f64,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub media: Vec<Media>,
    #[serde(default)]
    pub pinned: bool,
    #[serde(default)]
    pub keepers: i64,
    #[serde(default)]
    pub likes: i64,
    #[serde(default)]
    pub downloads: i64,
    #[serde(default)]
    pub reposts: i64,
    #[serde(default)]
    pub comments: Vec<Comment>,
    #[serde(rename = "commentCount", default)]
    pub comment_count: i64,
    #[serde(default)]
    pub liked: bool,
    #[serde(default)]
    pub kept: bool,
    #[serde(default)]
    pub reposted: bool,
    #[serde(default)]
    pub mine: bool,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub from: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub face: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub own: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub lp: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub n: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub views: Option<i64>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Page {
    #[serde(rename = "canWrite", default)]
    pub can_write: bool,
    #[serde(default)]
    pub posts: Vec<Seen>,
    #[serde(default)]
    pub at: f64,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub version: Option<String>,
}

/// A word of the wall (iOS MTBoardWord): «t» and what it carries; a field it does not carry is not written.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
pub struct Word {
    pub t: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub at: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub tx: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub md: Option<Vec<Media>>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub bn: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub bg: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub on: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub cid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub w: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub ps: Option<Vec<Seen>>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub v: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub fc: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub lp: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub hh: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub pv: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub vs: Option<Vec<String>>,
    /// «coin», «cmt», «cpay»: the coins given (iOS MTBoardWord.c) and the gift's own name, credited once (r)
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub c: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub r: Option<String>,
    /// «coin» of iOS 2304 (MTBoardWord.sd): the name of the SEND of the chain that carries the coins on the post -- the word carries
    /// none of its own
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub sd: Option<String>,
}

/// THE COINS OF COMMENTS (iOS MTBoardCoins, the author's words 04.10.2026 02:50 MSK: «20 percent of all coins for comments under a
/// post goes to the post's author»): a comment costs its writer one coin, carried to the wall's owner; four of every five burn and
/// the fifth goes to the post's writer.
pub const CMT: &str = "cmt:";
pub const CMT_BURN: &str = "cmt-burn:";
pub const CMT_PAY: &str = "cmt-pay:";
const FIFTH: i64 = 5;

/// A post of another's wall this machine keeps (iOS MTBoardKept): the post as its page carried it, the wall it stands on, whether
/// its download was told.
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Kept {
    pub post: Seen,
    pub wall: String,
    #[serde(default)]
    pub dl: bool,
}

impl Word {
    fn of(t: &str) -> Word {
        Word { t: t.into(), ..Default::default() }
    }
}

/// Who may write on my wall, and who may see it (iOS MTBoardRule): only me, everyone, my contacts, some -- chosen -- or everyone
/// but some; both start at «everyone». Windows keeps no contact book, so «contacts» admits nobody here.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Rule {
    pub rule: String,
    #[serde(default)]
    pub allow: Vec<String>,
    #[serde(default)]
    pub deny: Vec<String>,
}
impl Default for Rule {
    fn default() -> Rule {
        Rule { rule: "everyone".into(), allow: vec![], deny: vec![] }
    }
}
impl Rule {
    fn admits(&self, conv: &str) -> bool {
        if conv.is_empty() {
            return false;
        }
        match self.rule.as_str() {
            "onlyMe" | "contacts" => false,
            "some" => self.allow.iter().any(|a| a == conv),
            "except" => !self.deny.iter().any(|a| a == conv),
            _ => true,
        }
    }
}

/// What this machine keeps of the walls: mine, the pages of others, who speaks the wall, the version each was carried, the rules.
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Store {
    #[serde(default)]
    pub mine: Vec<Post>,
    #[serde(default)]
    pub pages: HashMap<String, Page>,
    #[serde(default)]
    pub cap: Vec<String>,
    #[serde(default)]
    pub sent: HashMap<String, String>,
    #[serde(default)]
    pub write: Rule,
    #[serde(default)]
    pub see: Rule,
    #[serde(default)]
    pub viewed: Vec<String>,
    /// the posts of other walls this machine keeps (iOS kept): saved, reposted or fetched whole
    #[serde(default)]
    pub kept: HashMap<String, Kept>,
    /// the post being written on each wall ("" mine), as its page was left (iOS drafts)
    #[serde(default)]
    pub drafts: HashMap<String, Draft>,
}

/// What a run holds besides: the versions heard, the asks and answers of the last seconds, the blocked.
#[derive(Default)]
struct Live {
    store: Option<Store>,
    heard: HashMap<String, String>,
    asked_at: HashMap<String, i64>,
    answered_at: HashMap<String, i64>,
    asks: Vec<String>,
    push: bool,
    seen_due: HashMap<String, Vec<String>>,
    blocked: HashSet<String>,
}

/// One wall per folder of a person (a test runs several at once).
static LIVE: Mutex<Option<HashMap<String, Live>>> = Mutex::new(None);

fn now_s() -> f64 {
    crate::wire::now_ms() as f64 / 1000.0
}

/// A post's own name (iOS UUID().uuidString): 36 characters, the hex uppercase.
pub fn fresh_id() -> String {
    let r = crate::crypto::random(16).unwrap_or_else(|| vec![0; 16]);
    let h = crate::wire::hex(&r).to_uppercase();
    format!("{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32])
}

/// The first letter of a name, as a face without a picture shows it (iOS MontanaAvatar.initial).
pub fn initial(name: &str) -> String {
    name.trim().chars().next().map(|c| c.to_uppercase().collect()).unwrap_or_else(|| "?".into())
}

/// The wall of this machine's person, read once a run (an unread wall is not an empty one) and kept beside the vault.
fn with<R>(vault: &Vault, f: impl FnOnce(&mut Live, &mut Store) -> R) -> R {
    let mut g = LIVE.lock().unwrap();
    let dir = vault.dir().to_string_lossy().to_string();
    let live = g.get_or_insert_with(HashMap::new).entry(dir).or_insert_with(|| Live { push: true, ..Default::default() });
    if live.store.is_none() {
        live.store = Some(vault.get(KEY).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default());
    }
    let mut store = live.store.take().unwrap();
    let r = f(live, &mut store);
    live.store = Some(store);
    r
}

fn save(vault: &Vault, s: &Store) {
    if let Ok(b) = serde_json::to_vec(s) {
        vault.set(KEY, &b);
    }
}

/// Whether the wall was read this run (the presence word names its version only then).
#[cfg(test)]
pub fn loaded(vault: &Vault) -> bool {
    LIVE.lock().unwrap().as_ref().and_then(|m| m.get(vault.dir().to_string_lossy().as_ref())).is_some_and(|l| l.store.is_some())
}

/// The blocked, as the walk last read them: a blocked person neither writes nor sees.
pub fn set_blocked(vault: &Vault, blocked: HashSet<String>) {
    with(vault, |l, _| l.blocked = blocked);
}

fn admits(l: &Live, r: &Rule, conv: &str) -> bool {
    !l.blocked.contains(conv) && r.admits(conv)
}

fn last_at(at: f64, comments: &[Comment]) -> f64 {
    comments.iter().map(|c| c.at).fold(at, f64::max)
}

/// Pinned first, then the newest record of its chain -- its birth or its latest comment (iOS ordered).
fn ordered(ps: &[Post]) -> Vec<Post> {
    let mut v = ps.to_vec();
    v.sort_by(|a, b| b.pinned.cmp(&a.pinned).then(last_at(b.at, &b.comments).partial_cmp(&last_at(a.at, &a.comments)).unwrap_or(std::cmp::Ordering::Equal)));
    v
}

/// The views move the version at every doubling (iOS viewStep): the number of the count's bits.
fn view_step(n: usize) -> u32 {
    if n == 0 { 0 } else { usize::BITS - n.leading_zeros() }
}

/// THE POSTS' PART OF THE VERSION (iOS postsTag): what a page shows of each post -- its name, pin, counts, faces, views, edit and
/// hidden comments -- under the page's shape; «0» for an empty wall.
fn posts_tag(mine: &[Post]) -> String {
    let shown: Vec<Post> = ordered(mine).into_iter().take(PAGE_SIZE).collect();
    if shown.is_empty() {
        return "0".into();
    }
    let mut s = format!("{PAGE_SHAPE};");
    for p in &shown {
        let faces = p.comments.iter().filter(|c| c.fc.is_some()).count() + usize::from(p.face.is_some());
        s += &format!("{}{}{}.{}.{}.{}.{}.{}.{}", p.id, if p.pinned { "p" } else { "" }, p.keepers.len(), p.likes.len(), p.downloads.len(),
                      p.reposts.len(), p.comments.len(), faces, view_step(p.views.as_ref().map_or(0, |v| v.len())));
        let hid = p.comments.iter().filter(|c| c.hid == Some(true)).count();
        s += &format!("{}z{};", p.ed.map(|e| format!("e{}", (e * 1000.0) as i64)).unwrap_or_default(), hid);
    }
    wire_tag(s.as_bytes())
}

/// The version said to one visitor (iOS spokenVersion): the posts' part and that visitor's own right to write; one the rule of
/// sight leaves out hears what an empty wall they may not write on says.
fn spoken_in(l: &Live, s: &Store, conv: &str) -> String {
    if !s.see.admits(conv) {
        return wire_tag(b"0r");
    }
    let bit = if s.write.admits(conv) { "w" } else { "r" };
    let _ = l;
    wire_tag(format!("{}{bit}", posts_tag(&s.mine)).as_bytes())
}

/// What my presence word says after the bio's tag to one correspondent (iOS heldTail «W»): my wall's version, once the wall of
/// that folder was read this run; nothing before.
pub fn tail_at(dir: &str, conv: &str) -> String {
    let mut g = LIVE.lock().unwrap();
    let Some(l) = g.as_mut().and_then(|m| m.get_mut(dir)) else { return String::new() };
    let Some(s) = l.store.take() else { return String::new() };
    let v = spoken_in(l, &s, conv);
    l.store = Some(s);
    format!("W{v}")
}

/// The version of my wall a presence word names to them; None while the wall is unread this run.
#[cfg(test)]
pub fn spoken(vault: &Vault, conv: &str) -> Option<String> {
    if !loaded(vault) {
        return None;
    }
    Some(with(vault, |l, s| spoken_in(l, s, conv)))
}

/// A comment as a page carries it to one visitor (iOS shown): only the two marks they may read -- theirs, or the owner's.
fn shown(c: &Comment, v: &str, conceal: bool) -> Comment {
    let mut x = c.clone();
    x.m = (!v.is_empty() && c.reference.as_deref() == Some(v)).then_some(true);
    x.o = (c.reference.as_deref() == Some("")).then_some(true);
    x.reference = None;
    if conceal && x.hid == Some(true) {
        x.text = String::new();
    }
    x
}

/// A post as one visitor sees it (iOS seen): counts, their own marks; «v» empty -- the owner.
fn seen(p: &Post, v: &str, conceal: bool) -> Seen {
    let comments: Vec<Comment> = if conceal { p.comments.iter().rev().take(COMMENTS_SHOWN).rev().cloned().collect() } else { p.comments.clone() };
    Seen {
        id: p.id.clone(), by_name: p.by_name.clone(), by_glyph: p.by_glyph.clone(), at: p.at, text: p.text.clone(), media: p.media.clone(),
        pinned: p.pinned, keepers: p.keepers.len() as i64, likes: p.likes.len() as i64, downloads: p.downloads.len() as i64,
        reposts: p.reposts.len() as i64, comments: comments.iter().map(|c| shown(c, v, conceal)).collect(), comment_count: p.comments.len() as i64,
        liked: p.likes.iter().any(|x| x == v), kept: p.keepers.iter().any(|x| x == v), reposted: p.reposts.iter().any(|x| x == v),
        mine: p.author == v, from: p.from.clone(), face: if p.author.is_empty() && p.from.is_none() { None } else { p.face.clone() },
        // A REPOST OF THE OWNER'S OWN POST IS THE OWNER'S TOO (iOS seen): the visitor is told its writer is the page's owner
        own: Some(p.author.is_empty() && (p.from.is_none() || p.src_by.as_deref() == Some(""))), lp: p.lp.clone(), n: p.n,
        views: Some(p.views.as_ref().map_or(0, |v| v.len()) as i64),
    }
}

fn clean_media(md: &[Media]) -> Vec<Media> {
    md.iter().take(MEDIA_LIMIT).filter(|m| ["img", "vid", "aud", "doc"].contains(&m.kind.as_str())).enumerate().map(|(i, m)| {
        let mut x = m.clone();
        x.name = x.name.chars().take(200).collect();
        x.ext = x.ext.chars().filter(|c| c.is_ascii_alphanumeric()).take(8).collect::<String>().to_lowercase();
        // a page carries the posters of a post's first four files only (iOS clean): the rest are brought when looked at
        if i >= 4 || x.thumb.as_ref().is_some_and(|t| t.len() > THUMB_LIMIT) {
            x.thumb = None;
        }
        x
    }).collect()
}

/// A post from another machine held to what a post can be (iOS clean): the words cut, the files and the counts bounded.
fn clean_seen(s: &Seen) -> Seen {
    let mut x = s.clone();
    x.text = x.text.chars().take(TEXT_LIMIT).collect();
    x.by_name = x.by_name.chars().filter(|c| !c.is_control()).take(64).collect();
    x.by_glyph = x.by_glyph.chars().take(8).collect();
    x.media = clean_media(&x.media);
    x.comments = x.comments.iter().rev().take(COMMENTS_KEPT).rev().map(|c| {
        let mut c = c.clone();
        c.text = c.text.chars().take(COMMENT_LIMIT).collect();
        c.by = c.by.chars().take(64).collect();
        if c.fc.as_ref().is_some_and(|f| f.len() > FACE_LIMIT) {
            c.fc = None;
        }
        c
    }).collect();
    if x.face.as_ref().is_some_and(|f| f.len() > FACE_LIMIT) {
        x.face = None;
    }
    x
}

/// THE COMMENT'S SEAL (iOS MTBoard.seal): SHA-256 of its name, its moment in UTC to the millisecond, the seal before it and its
/// words, in hex -- each comment seals the one before, a chain under every post.
pub fn seal(c: &Comment) -> String {
    let prev = c.pv.clone().unwrap_or_else(|| ZERO.into());
    crate::wire::hex(&crate::wire::sha(&[format!("{}\n{}\n{prev}\n{}", c.id, stamp(c.at), c.text).as_bytes()]))
}

/// THE GEMATRIA OF A SEAL (iOS MTBoard.gematria): the hex number read in base 29, each digit counted as its prime -- the wall's
/// own count, and every letter's.
pub fn gematria(hex: &str) -> i64 {
    const PRIMES: [i64; 29] = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109];
    let mut digits: Vec<u32> = Vec::with_capacity(hex.len());
    for ch in hex.chars() {
        match ch.to_digit(16) {
            Some(v) => digits.push(v),
            None => return 0,
        }
    }
    if hex.is_empty() {
        return PRIMES[0];
    }
    let mut total = 0;
    loop {
        let (mut rem, mut next, mut started) = (0u32, Vec::with_capacity(digits.len()), false);
        for &v in &digits {
            let cur = rem * 16 + v;
            let q = cur / 29;
            rem = cur % 29;
            if q != 0 || started {
                next.push(q);
                started = true;
            }
        }
        total += PRIMES[rem as usize];
        if next.is_empty() {
            break;
        }
        digits = next;
    }
    total
}

/// THE SEAL OF A LETTER AND ITS GEMATRIA (iOS MTLetterSeal): SHA-256 over the letter's one wire name, the same on both sides; its
/// stamp wears the gematria, and the head of the seal while the chat's Money Flow is on. A row without a wire name wears none.
pub fn letter_mark(mid: &str) -> Option<(String, i64)> {
    static KEPT: std::sync::Mutex<Option<std::collections::HashMap<String, (String, i64)>>> = std::sync::Mutex::new(None);
    let core = mid.strip_prefix("mid:").unwrap_or(mid);
    let wire = core.strip_prefix('t').and_then(|r| r.split_once('-')).is_some_and(|(ms, id)| {
        !ms.is_empty() && ms.bytes().all(|b| b.is_ascii_digit()) && id.len() == 36
    });
    if !wire {
        return None;
    }
    let mut g = KEPT.lock().unwrap();
    let kept = g.get_or_insert_with(Default::default);
    if let Some(k) = kept.get(core) {
        return Some(k.clone());
    }
    let h = crate::wire::hex(&crate::wire::sha(&[format!("montana-letter-seal\nmid:{core}").as_bytes()]));
    let k = (h[..8].to_string(), gematria(&h));
    if kept.len() >= 4096 {
        kept.clear();
    }
    kept.insert(core.to_string(), k.clone());
    Some(k)
}

/// A moment as the seal writes it (iOS stamp): 2026-10-21T15:04:05.123Z.
pub fn stamp(at: f64) -> String {
    let mut sec = at.trunc() as i64;
    let mut ms = ((at - sec as f64) * 1000.0 + 0.5) as i64;
    if ms == 1000 {
        ms = 0;
        sec += 1;
    }
    let ms = ms.max(0);
    let (y, mo, d, h, mi, s) = civil(sec);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}.{ms:03}Z")
}

/// Seconds of the epoch as the calendar's day and time in UTC (days from civil, Howard Hinnant).
fn civil(sec: i64) -> (i64, i64, i64, i64, i64, i64) {
    let days = sec.div_euclid(86_400);
    let rem = sec.rem_euclid(86_400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    (y, m, d, rem / 3600, rem % 3600 / 60, rem % 60)
}

fn toggle(set: &mut Vec<String>, who: &str, on: bool) {
    set.retain(|x| x != who);
    if on {
        set.push(who.to_string());
    }
}

/// The words a heard word asks this machine to say: to whom, and what.
pub type Said = Vec<(String, Word)>;

/// The posts my wall gives a visitor (iOS sendPage): nothing to one the rule of sight leaves out.
fn page_for(l: &Live, s: &Store, conv: &str) -> Word {
    let sees = admits(l, &s.see, conv);
    let ps: Vec<Seen> = if sees { ordered(&s.mine).iter().take(PAGE_SIZE).map(|p| clean_seen(&seen(p, conv, true))).collect() } else { vec![] };
    Word { t: "page".into(), w: Some(sees && admits(l, &s.write, conv)), ps: Some(ps), v: Some(spoken_in(l, s, conv)), ..Default::default() }
}

fn learn_cap(l: &mut Live, s: &mut Store, conv: &str) -> bool {
    if conv.is_empty() || conv.starts_with("grp:") || s.cap.iter().any(|c| c == conv) {
        return false;
    }
    s.cap.push(conv.to_string());
    l.push = true;
    true
}

/// A WORD OF THE WALL HEARD (iOS MTBoard.apply): what changed is kept, what it asks for is said back.
pub fn apply(vault: &Vault, w: &Word, conv: &str, names: &dyn Fn(&str) -> String) -> Said {
    let now = now_s();
    let mut said: Said = vec![];
    with(vault, |l, s| {
        let mut dirty = learn_cap(l, s, conv);
        let mut own_moved = false;
        let id = w.id.clone().unwrap_or_default();
        match w.t.as_str() {
            "post" => {
                if id.is_empty() {
                    return;
                }
                if !admits(l, &s.write, conv) || !admits(l, &s.see, conv) {
                    said.push((conv.into(), Word { id: Some(id), ..Word::of("no") }));
                    return;
                }
                if s.mine.iter().any(|p| p.id == id) {
                    return;
                }
                if s.mine.iter().filter(|p| p.author == conv).count() >= POSTS_PER_WRITER || s.mine.len() >= WALL_LIMIT {
                    said.push((conv.into(), Word { id: Some(id), ..Word::of("no") }));
                    return;
                }
                let name = w.bn.clone().filter(|n| !n.is_empty()).map(|n| n.chars().take(64).collect()).unwrap_or_else(|| names(conv));
                let glyph = w.bg.clone().filter(|g| !g.is_empty()).map(|g| g.chars().take(8).collect()).unwrap_or_else(|| initial(&name));
                s.mine.push(Post {
                    id, author: conv.into(), by_name: name, by_glyph: glyph, at: w.at.unwrap_or(now).min(now),
                    text: w.tx.clone().unwrap_or_default().chars().take(TEXT_LIMIT).collect(), media: clean_media(w.md.as_deref().unwrap_or(&[])),
                    keepers: vec![conv.into()], face: w.fc.clone().filter(|f| !f.is_empty() && f.len() <= FACE_LIMIT), lp: w.lp.clone(),
                    ..Default::default()
                });
                number_missing(&mut s.mine);
                own_moved = true;
            }
            "no" | "drop" => {
                if let Some(pg) = s.pages.get_mut(conv) {
                    pg.posts.retain(|p| p.id != id);
                    dirty = true;
                }
            }
            "ask" => {
                // one answer to one correspondent in thirty seconds: asks piled up cost the owner one page
                let t = crate::wire::now_ms() / 1000;
                if t - l.answered_at.get(conv).copied().unwrap_or(0) < ANSWER_S {
                    return;
                }
                l.answered_at.insert(conv.into(), t);
                said.push((conv.into(), page_for(l, s, conv)));
            }
            "page" => {
                let posts: Vec<Seen> = w.ps.clone().unwrap_or_default().iter().take(PAGE_SIZE).map(clean_seen).collect();
                // my own wall never stands as another's (iOS isEcho): a page of nothing but my posts came back to me
                if !posts.is_empty() && posts.iter().all(|p| s.mine.iter().any(|m| m.id == p.id)) {
                    return;
                }
                let fresh = Page { can_write: w.w.unwrap_or(false), posts, at: now, version: w.v.clone() };
                let page = match s.pages.get(conv) {
                    Some(old) => keep_mine(old, fresh, now),
                    None => fresh,
                };
                s.pages.insert(conv.into(), page);
                while s.pages.len() > WALLS {
                    let oldest = s.pages.iter().min_by(|a, b| a.1.at.partial_cmp(&b.1.at).unwrap_or(std::cmp::Ordering::Equal)).map(|(k, _)| k.clone());
                    if let Some(k) = oldest {
                        s.pages.remove(&k);
                    }
                }
                dirty = true;
            }
            "like" | "keep" | "dl" | "rp" if admits(l, &s.see, conv) => {
                if let Some(p) = s.mine.iter_mut().find(|p| p.id == id) {
                    let on = w.on.unwrap_or(true) || w.t == "dl" || w.t == "rp";
                    match w.t.as_str() {
                        "like" => toggle(&mut p.likes, conv, on),
                        "keep" => toggle(&mut p.keepers, conv, on),
                        "dl" => toggle(&mut p.downloads, conv, true),
                        _ => toggle(&mut p.reposts, conv, true),
                    }
                    own_moved = true;
                }
            }
            "view" if admits(l, &s.see, conv) => {
                for vid in w.vs.clone().unwrap_or_default().iter().take(PAGE_SIZE) {
                    if let Some(p) = s.mine.iter_mut().find(|p| &p.id == vid && p.author != conv) {
                        let v = p.views.get_or_insert_with(Vec::new);
                        if !v.iter().any(|x| x == conv) {
                            v.push(conv.into());
                            own_moved = true;
                        }
                    }
                }
            }
            "cmt" => {
                if !admits(l, &s.see, conv) || !admits(l, &s.write, conv) {
                    return;
                }
                let text = w.tx.clone().unwrap_or_default().trim().to_string();
                if text.is_empty() {
                    return;
                }
                let name = w.bn.clone().filter(|n| !n.is_empty()).map(|n| n.chars().take(64).collect()).unwrap_or_else(|| names(conv));
                let mut c = Comment {
                    id: w.cid.clone().unwrap_or_else(fresh_id), glyph: w.bg.clone().filter(|g| !g.is_empty()).map(|g| g.chars().take(8).collect()).unwrap_or_else(|| initial(&name)),
                    by: name, text: text.chars().take(COMMENT_LIMIT).collect(), at: w.at.unwrap_or(now).min(now), reference: Some(conv.into()),
                    fc: w.fc.clone().filter(|f| !f.is_empty() && f.len() <= FACE_LIMIT), h: w.hh.clone(), pv: w.pv.clone(), ..Default::default()
                };
                if let Some(p) = s.mine.iter_mut().find(|p| p.id == id) {
                    if !p.comments.iter().any(|x| x.id == c.id) {
                        if c.h.is_none() {
                            c.pv = Some(p.comments.last().and_then(|x| x.h.clone()).unwrap_or_else(|| ZERO.into()));
                            c.h = Some(seal(&c));
                        }
                        p.comments.push(c);
                        if p.comments.len() > COMMENTS_KEPT {
                            let cut = p.comments.len() - COMMENTS_KEPT;
                            p.comments.drain(..cut);
                        }
                        own_moved = true;
                    }
                }
                // THE COMMENT'S COIN (iOS, 04.10): one coin, taken once by its name, into the post's count -- every fifth to its writer
                if let (Some(1), Some(r)) = (w.c, w.r.as_deref().filter(|r| !r.is_empty() && r.len() <= 64)) {
                    if s.mine.iter().any(|p| p.id == id)
                        && crate::coins::moved(vault, "receive", 1, &format!("{CMT}{r}"), Some(conv), Some(&format!("post:{id}"))) {
                        if let Some(pay) = comment_coin(vault, s, &id, r) {
                            said.push(pay);
                        }
                        own_moved = true;
                    }
                }
                // the commenter sees every comment: answered as an ask is, with the page as it stands
                let t = crate::wire::now_ms() / 1000;
                if t - l.answered_at.get(conv).copied().unwrap_or(0) >= ANSWER_S {
                    l.answered_at.insert(conv.into(), t);
                    said.push((conv.into(), page_for(l, s, conv)));
                }
            }
            "del" => {
                // only the wall's owner takes a post off their wall: a writer's «del» says their machine keeps its files no more
                if let Some(p) = s.mine.iter_mut().find(|p| p.id == id && p.keepers.iter().any(|k| k == conv)) {
                    p.keepers.retain(|k| k != conv);
                    own_moved = true;
                }
            }
            // COINS GIVEN ON MY POST (iOS, the author's word 03.10 13:40): credited once by the gift's name, on the post's own row.
            // A SEND OF THE CHAIN (iOS 2304 MTBoard.coin): the word names it and the post, the coins come by the scan alone; a build
            // before still carries the coins in the word
            "coin" if admits(l, &s.see, conv) => {
                if let Some(tx) = w.sd.as_deref() {
                    crate::wallet::heard(vault, tx, &format!("post:{id}"));
                } else if let (Some(c), Some(r)) = (w.c.filter(|c| *c > 0), w.r.as_deref().filter(|r| !r.is_empty() && r.len() <= 64)) {
                    if s.mine.iter().any(|p| p.id == id) {
                        crate::coins::moved(vault, "receive", c, &format!("post:{r}"), Some(conv), Some(&format!("post:{id}")));
                    }
                }
            }
            // MY FIFTH OF A POST'S COMMENTS (iOS cpay): the wall's owner pays the writer of a post this machine keeps on that wall
            "cpay" => {
                if let (Some(1), Some(r)) = (w.c, w.r.as_deref().filter(|r| !r.is_empty() && r.len() <= 64)) {
                    if s.kept.get(&id).is_some_and(|k| k.wall == conv) {
                        crate::coins::moved(vault, "receive", 1, &format!("{CMT_PAY}{r}"), Some(conv), Some(&format!("post:{id}")));
                    }
                }
            }
            // «hi» says only that its build reads the wall (learnCap above); channels' words and newer shapes: silence
            _ => {}
        }
        if own_moved {
            l.push = true;
            dirty = true;
        }
        if dirty {
            save(vault, s);
        }
    });
    said
}

/// What I wrote stays until the owner's page says it (iOS keepMine): my comments and my posts not yet on the page, for half an hour.
fn keep_mine(old: &Page, mut new: Page, now: f64) -> Page {
    let since = now - 1800.0;
    for o in &old.posts {
        if let Some(n) = new.posts.iter_mut().find(|p| p.id == o.id) {
            let have: HashSet<String> = n.comments.iter().map(|c| c.id.clone()).collect();
            let mine: Vec<Comment> = o.comments.iter().filter(|c| c.m == Some(true) && !have.contains(&c.id) && since < c.at).cloned().collect();
            if !mine.is_empty() {
                n.comment_count += mine.len() as i64;
                n.comments.extend(mine);
                n.comments.sort_by(|a, b| a.at.partial_cmp(&b.at).unwrap_or(std::cmp::Ordering::Equal));
            }
        } else if o.mine && since < o.at {
            new.posts.push(o.clone());
        }
    }
    new
}

/// Every post of my wall gets its number once, the next after the highest, in the order of birth (iOS numberMissing).
fn number_missing(mine: &mut [Post]) {
    let mut top = mine.iter().filter_map(|p| p.n).max().unwrap_or(0);
    let mut order: Vec<usize> = (0..mine.len()).collect();
    order.sort_by(|a, b| mine[*a].at.partial_cmp(&mine[*b].at).unwrap_or(std::cmp::Ordering::Equal));
    for i in order {
        if mine[i].n.is_none() {
            top += 1;
            mine[i].n = Some(top);
        }
    }
}

/// A CORRESPONDENT'S PRESENCE WORD NAMED THEIR WALL'S VERSION (iOS heard(version:)): their build speaks the wall; a page that
/// differs is asked for, once a minute at most.
pub fn heard_version(vault: &Vault, conv: &str, v: &str) {
    with(vault, |l, s| {
        l.heard.insert(conv.into(), v.into());
        if learn_cap(l, s, conv) {
            save(vault, s);
        }
        if s.pages.get(conv).and_then(|p| p.version.as_deref()) != Some(v) {
            ask_in(l, conv);
        }
    });
}

fn ask_in(l: &mut Live, conv: &str) {
    let t = crate::wire::now_ms() / 1000;
    if t - l.asked_at.get(conv).copied().unwrap_or(0) < ASK_S {
        return;
    }
    l.asked_at.insert(conv.into(), t);
    if !l.asks.iter().any(|a| a == conv) {
        l.asks.push(conv.into());
    }
}

/// A person's page is looked at (iOS look): a wall not held, or held from more than ten minutes ago, is asked.
pub fn look(vault: &Vault, wall: &str) {
    with(vault, |l, s| {
        if s.pages.get(wall).is_some_and(|p| now_s() - p.at < LOOK_STALE_S) {
            return;
        }
        ask_in(l, wall);
    });
}

/// THE WALK OF THE WALL (iOS pushDue / ask / tellSeen): the asks due, the pages whose version moved for each correspondent who
/// speaks the wall (the latest first, 128 at most; one who may no longer see gets the empty page once), the views told.
/// `latest`: the correspondents, the latest first.
pub fn due(vault: &Vault, latest: &[String]) -> Said {
    let mut said: Said = vec![];
    with(vault, |l, s| {
        for a in std::mem::take(&mut l.asks) {
            said.push((a, Word::of("ask")));
        }
        for (wall, ids) in std::mem::take(&mut l.seen_due) {
            s.viewed.extend(ids.iter().map(|i| format!("{wall}#{i}")));
            if s.viewed.len() > VIEWED_KEPT {
                let cut = s.viewed.len() - VIEWED_KEPT;
                s.viewed.drain(..cut);
            }
            said.push((wall, Word { vs: Some(ids), ..Word::of("view") }));
        }
        if l.push {
            l.push = false;
            let mut due: Vec<String> = latest.iter().filter(|c| s.cap.contains(c)).take(PUSH_TO).cloned().collect();
            let refused = wire_tag(b"0r");
            for (c, v) in &s.sent {
                if *v != refused && !s.see.admits(c) && !due.contains(c) {
                    due.push(c.clone());
                }
            }
            for c in due {
                let v = spoken_in(l, s, &c);
                if s.sent.get(&c) != Some(&v) {
                    said.push((c.clone(), page_for(l, s, &c)));
                }
            }
        }
    });
    said
}

/// A page carried and taken by the network: the version that visitor now holds (iOS delivered).
pub fn page_sent(vault: &Vault, conv: &str, v: &str) {
    with(vault, |_, s| {
        s.sent.insert(conv.into(), v.into());
        save(vault, s);
    });
}

/// A page that did not leave is carried again by the next walk.
pub fn push_again(vault: &Vault) {
    with(vault, |l, _| l.push = true);
}

/// The wall as the window draws it: mine as its owner sees it, another's as its owner last sent it.
pub fn posts(vault: &Vault, wall: Option<&str>) -> (Vec<Seen>, bool, bool) {
    with(vault, |_, s| match wall {
        None => (ordered(&s.mine).iter().map(|p| seen(p, "", false)).collect(), true, true),
        Some(w) => {
            let mut ps = s.pages.get(w).map(|p| p.posts.clone()).unwrap_or_default();
            ps.sort_by(|a, b| b.pinned.cmp(&a.pinned).then(last_at(b.at, &b.comments).partial_cmp(&last_at(a.at, &a.comments)).unwrap_or(std::cmp::Ordering::Equal)));
            let held = s.pages.contains_key(w);
            (ps, s.pages.get(w).is_some_and(|p| p.can_write), held)
        }
    })
}

/// WHERE A POST STANDS on this machine (iOS MTBoard.place): Some("") -- my wall, Some(reference) -- a correspondent's.
pub fn place(vault: &Vault, id: &str) -> Option<String> {
    with(vault, |_, s| {
        if s.mine.iter().any(|p| p.id == id) {
            return Some(String::new());
        }
        let mut walls: Vec<&String> = s.pages.keys().collect();
        walls.sort();
        walls.into_iter().find(|w| s.pages[*w].posts.iter().any(|p| p.id == id)).cloned()
    })
}
/// A path's piece as it was written: «%D0%90» back to «А» (a short link's name, iOS addingPercentEncoding(.urlPathAllowed)).
fn percent_decoded(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    let hex = |c: u8| (c as char).to_digit(16).map(|d| d as u8);
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let (Some(h), Some(l)) = (hex(b[i + 1]), hex(b[i + 2])) {
                out.push(h * 16 + l);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}
/// The same piece written for a link: what a path takes as it is (iOS .urlPathAllowed) stays, every other byte is «%XX».
pub fn percent_encoded(s: &str) -> String {
    s.bytes().map(|c| if c.is_ascii_alphanumeric() || b"-._~!$&'()*+,;=:@".contains(&c) { (c as char).to_string() } else { format!("%{c:02X}") }).collect()
}
/// A POST'S LINK (iOS MTBoard.linkPost(p, on:)): the short «montana://wall/@<name>/<number>» where the wall's owner claims a name and
/// the post has its number on that wall; else the long «montana://wall/post/<id>».
pub fn link_post(owner_name: &str, p: &Seen) -> String {
    match (p.n, claimed_name(owner_name)) {
        (Some(n), Some(c)) => format!("montana://wall/{}/{n}", percent_encoded(&format!("@{c}"))),
        _ => format!("montana://wall/post/{}", p.id),
    }
}
/// The name a wall's owner claims after «@» in their name (iOS MTBoard.claimedName(in:)): «Алиса @alice» -- alice.
pub fn claimed_name(name: &str) -> Option<String> {
    let tail: String = name.rsplit_once('@')?.1.chars().take_while(|c| !c.is_whitespace()).collect();
    (!tail.is_empty()).then_some(tail)
}
/// THE POST, AND THE COMMENT, A WALL'S LINK NAMES among the posts this machine holds (iOS MTBoardComments.target, MTBoard.find):
/// «montana://wall/post/<id>», «…/comment/<post>/<comment>», and the short «…/@<name>/<number>[/<comment's number>]» -- the wall
/// whose owner claims that name (`name_of` gives each wall's name, None my own) and the post of that number on it. The wall it
/// stands on ("" mine), the post, the comment.
pub fn target(vault: &Vault, link: &str, name_of: &dyn Fn(Option<&str>) -> String) -> Option<(String, String, Option<String>)> {
    let rest = link.trim().strip_prefix("montana://").filter(|r| r.to_lowercase().starts_with("wall/"))?;
    let parts: Vec<String> = rest[5..].split('/').filter(|x| !x.is_empty()).map(|x| x.split(['?', '#']).next().unwrap_or("").to_string()).collect();
    match parts.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        ["post", id] => place(vault, id).map(|w| (w, id.to_string(), None)),
        ["comment", id, c] => place(vault, id).map(|w| (w, id.to_string(), Some(c.to_string()))),
        [head, n, ..] if head.starts_with('@') && parts.len() <= 3 => {
            let want = percent_decoded(head.trim_start_matches('@')).to_lowercase();
            let (n, k) = (n.parse::<i64>().ok()?, parts.get(2).and_then(|k| k.parse::<i64>().ok()));
            let mut walls: Vec<Option<String>> = vec![None];
            walls.extend(with(vault, |_, s| { let mut w: Vec<String> = s.pages.keys().cloned().collect(); w.sort(); w }).into_iter().map(Some));
            for w in walls {
                if claimed_name(&name_of(w.as_deref())).map(|x| x.to_lowercase()) != Some(want.clone()) {
                    continue;
                }
                let (ps, _, _) = posts(vault, w.as_deref());
                let Some(p) = ps.iter().find(|p| p.n == Some(n)) else { continue };
                let cid = k.and_then(|k| {
                    let i = k - (p.comment_count - p.comments.len() as i64) - 1;
                    usize::try_from(i).ok().and_then(|i| p.comments.get(i)).map(|c| c.id.clone())
                });
                return Some((w.unwrap_or_default(), p.id.clone(), cid));
            }
            None
        }
        _ => None,
    }
}

/// THE WALL'S DRAFT (iOS MTBoard.draft / lay / dropDraft): the post being written on a wall, as its page was left; laid at every
/// change, and the files it no longer holds are named back so their copies can go.
pub fn draft(vault: &Vault, wall: Option<&str>) -> Option<Draft> {
    with(vault, |_, s| s.drafts.get(wall.unwrap_or("")).cloned())
}
pub fn lay_draft(vault: &Vault, wall: Option<&str>, mut d: Draft) -> Vec<String> {
    d.text = d.text.chars().take(TEXT_LIMIT).collect();
    d.files.truncate(MEDIA_LIMIT);
    for f in &mut d.files {
        f.name = f.name.chars().filter(|c| !c.is_control()).take(200).collect();
        f.ext = f.ext.chars().filter(|c| c.is_ascii_alphanumeric()).take(8).collect::<String>().to_lowercase();
        if f.thumb.as_ref().is_some_and(|t| t.len() > THUMB_LIMIT) {
            f.thumb = None;
        }
    }
    d.files.retain(|f| f.file.starts_with("wd_") && ["img", "vid", "aud", "doc"].contains(&f.kind.as_str()));
    with(vault, |_, s| {
        let key = wall.unwrap_or("").to_string();
        let gone: Vec<String> = s.drafts.get(&key).map(|o| o.files.iter().filter(|f| !d.files.iter().any(|x| x.file == f.file)).map(|f| f.file.clone()).collect())
            .unwrap_or_default();
        if d.text.trim().is_empty() && d.files.is_empty() {
            s.drafts.remove(&key);
        } else {
            s.drafts.insert(key, d);
        }
        save(vault, s);
        gone
    })
}
/// The draft thrown away or published: its files named back (published, they are already the post's own).
pub fn drop_draft(vault: &Vault, wall: Option<&str>) -> Vec<String> {
    with(vault, |_, s| {
        let gone = s.drafts.remove(wall.unwrap_or("")).map(|d| d.files.into_iter().map(|f| f.file).collect()).unwrap_or_default();
        save(vault, s);
        gone
    })
}

/// Whether I may write on a wall (iOS canWrite): mine always; another's as its owner's page last said.
pub fn can_write(vault: &Vault, wall: Option<&str>) -> bool {
    wall.is_none_or(|w| with(vault, |_, s| s.pages.get(w).is_some_and(|p| p.can_write)))
}

/// WHO WROTE A POST, AS THIS MACHINE KNOWS THEM (iOS MTBoard.writer): Some("") -- me, Some(reference) -- a correspondent, None --
/// nobody this machine was told of. A repost wears the writer of the post it took.
pub fn writer(vault: &Vault, wall: Option<&str>, p: &Seen) -> Option<String> {
    with(vault, |_, s| writer_in(s, wall, p))
}
fn writer_in(s: &Store, wall: Option<&str>, p: &Seen) -> Option<String> {
    let Some(w) = wall else {
        let Some(q) = s.mine.iter().find(|q| q.id == p.id) else { return p.mine.then(String::new) };
        if q.from.is_some() {
            return q.src_by.clone().or_else(|| original_writer(s, &p.id, None));
        }
        return Some(q.author.clone());
    };
    if p.from.is_some() {
        return if p.own == Some(true) { Some(w.into()) } else { original_writer(s, &p.id, Some(w)) };
    }
    if p.mine {
        return Some(String::new());
    }
    (p.own == Some(true)).then(|| w.to_string())
}
/// The post itself where it stands as itself on a wall this machine holds -- the first such wall by its reference, so the answer
/// never depends on the order a map walks in (iOS original).
fn original(s: &Store, id: &str, besides: Option<&str>) -> Option<(String, Seen)> {
    let mut walls: Vec<&String> = s.pages.keys().collect();
    walls.sort();
    walls.into_iter().filter(|w| Some(w.as_str()) != besides)
        .find_map(|w| s.pages[w].posts.iter().find(|q| q.id == id && q.from.is_none()).map(|o| (w.clone(), o.clone())))
}
fn original_writer(s: &Store, id: &str, besides: Option<&str>) -> Option<String> {
    if besides.is_some() {
        if let Some(q) = s.mine.iter().find(|q| q.id == id && q.from.is_none()) {
            return Some(q.author.clone());
        }
    }
    let (w, o) = original(s, id, besides)?;
    writer_in(s, Some(&w), &o)
}
/// THE WALL A REPOST CAME FROM (iOS MTBoard.source): Some("") -- my own wall, Some(reference) -- a correspondent's, None -- this
/// machine holds the post nowhere as itself and the repost's line stays a word.
pub fn source(vault: &Vault, wall: Option<&str>, p: &Seen) -> Option<String> {
    with(vault, |_, s| {
        if wall.is_none() {
            let q = s.mine.iter().find(|q| q.id == p.id && q.from.is_some())?;
            if let Some(src) = &q.src {
                return Some(src.clone());
            }
        } else if s.mine.iter().any(|q| q.id == p.id && q.from.is_none()) {
            return Some(String::new());
        }
        original(s, &p.id, wall).map(|(w, _)| w)
    })
}

/// THE WALL OF THOUGHTS (iOS feed): every post of my own wall and of every wall of my people this machine holds, each once, the
/// newest first; a wall of one blocked or gone stands out of it.
pub fn feed(vault: &Vault, holds: &dyn Fn(&str) -> bool) -> Vec<(String, Seen)> {
    with(vault, |l, s| {
        let mut all: Vec<(String, Seen)> = s.mine.iter().map(|p| (String::new(), seen(p, "", false))).collect();
        for (wall, pg) in &s.pages {
            if l.blocked.contains(wall) || !holds(wall) {
                continue;
            }
            all.extend(pg.posts.iter().map(|p| (wall.clone(), p.clone())));
        }
        let mut once = HashSet::new();
        all.retain(|(w, p)| once.insert(format!("{w}/{}", p.id)));
        all.sort_by(|a, b| b.1.at.partial_cmp(&a.1.at).unwrap_or(std::cmp::Ordering::Equal).then(b.1.id.cmp(&a.1.id)));
        all.truncate(5000);
        all
    })
}

/// My post on my own wall (iOS publish → mine): its files already on the node.
pub fn post_mine(vault: &Vault, id: &str, name: &str, text: &str, media: Vec<Media>, lp: Option<String>) {
    with(vault, |l, s| {
        s.mine.push(Post {
            id: id.into(), author: String::new(), by_name: name.into(), by_glyph: initial(name), at: now_s(),
            text: text.chars().take(TEXT_LIMIT).collect(), media, keepers: vec![String::new()], lp, ..Default::default()
        });
        number_missing(&mut s.mine);
        l.push = true;
        save(vault, s);
    });
}

/// My post on another's wall (iOS publish → send «post»): the word to the owner, and the post on their page here until their
/// page says it.
#[allow(clippy::too_many_arguments)]
pub fn post_on(vault: &Vault, wall: &str, id: &str, name: &str, text: &str, media: Vec<Media>, lp: Option<String>, face: Option<String>) -> Word {
    let at = now_s();
    let text: String = text.chars().take(TEXT_LIMIT).collect();
    // MY FACE, SMALL, OVER A POST I WRITE ON ANOTHER'S WALL (iOS myFace): the owner keeps it with the post, a visitor sees it
    let face = face.filter(|f| !f.is_empty() && f.len() <= FACE_LIMIT);
    with(vault, |l, s| {
        let fresh = Seen {
            id: id.into(), by_name: name.into(), by_glyph: initial(name), at, text: text.clone(), media: media.clone(), keepers: 1,
            kept: true, mine: true, own: Some(false), lp: lp.clone(), face: face.clone(), ..Default::default()
        };
        let pg = s.pages.entry(wall.into()).or_insert_with(|| Page { can_write: true, posts: vec![], at, version: None });
        let at_ = pg.posts.iter().position(|p| !p.pinned).unwrap_or(pg.posts.len());
        pg.posts.insert(at_, fresh.clone());
        // the writer keeps their post from the start (iOS becomePeer): its fifth of the comments' coins comes to it (cpay)
        s.kept.insert(id.into(), Kept { post: fresh, wall: wall.into(), dl: true });
        ask_in(l, wall);
        save(vault, s);
    });
    Word { id: Some(id.into()), at: Some(at), tx: Some(text), md: Some(media), bn: Some(name.into()), bg: Some(initial(name)), fc: face, lp, ..Word::of("post") }
}

/// A like (iOS like): on my wall my own mark; on another's the word to its owner and the count as it will stand.
pub fn like(vault: &Vault, wall: Option<&str>, id: &str) -> Option<(String, Word)> {
    with(vault, |l, s| {
        let out = match wall {
            None => {
                let p = s.mine.iter_mut().find(|p| p.id == id)?;
                let on = !p.likes.iter().any(|x| x.is_empty());
                toggle(&mut p.likes, "", on);
                l.push = true;
                None
            }
            Some(w) => {
                let p = s.pages.get_mut(w)?.posts.iter_mut().find(|p| p.id == id)?;
                let on = !p.liked;
                p.liked = on;
                p.likes = (p.likes + if on { 1 } else { -1 }).max(0);
                Some((w.to_string(), Word { id: Some(id.into()), on: Some(on), ..Word::of("like") }))
            }
        };
        save(vault, s);
        out
    })
}

/// A comment (iOS comment): sealed after the last seal of its post; on my wall it stands at once, on another's it goes to its
/// owner and stands as mine until their page says it. A COMMENT COSTS ONE COIN (the author's words 04.10.2026 02:50 MSK): carried to
/// the wall's owner, never more than the balance holds -- a comment is never refused for want of coins.
pub fn comment(vault: &Vault, wall: Option<&str>, id: &str, name: &str, text: &str, face: Option<String>) -> Said {
    let t: String = text.trim().chars().take(COMMENT_LIMIT).collect();
    if t.is_empty() {
        return vec![];
    }
    let r = fresh_id();
    with(vault, |l, s| {
        let last = match wall {
            None => s.mine.iter().find(|p| p.id == id).map(|p| p.comments.last().and_then(|c| c.h.clone())),
            Some(w) => s.pages.get(w).and_then(|pg| pg.posts.iter().find(|p| p.id == id)).map(|p| p.comments.last().and_then(|c| c.h.clone())),
        };
        let Some(last) = last else { return vec![] };
        // MY FACE OVER A COMMENT (iOS commentFace, the author's word 25.09): small, carried with the comment's words
        let fc = face.filter(|f| !f.is_empty() && f.len() <= FACE_LIMIT);
        let mut c = Comment { id: fresh_id(), by: name.into(), glyph: initial(name), text: t, at: now_s(), pv: Some(last.unwrap_or_else(|| ZERO.into())), fc,
                              ..Default::default() };
        c.h = Some(seal(&c));
        let mut out: Said = vec![];
        match wall {
            None => {
                if let Some(p) = s.mine.iter_mut().find(|p| p.id == id) {
                    let mut mc = c.clone();
                    mc.reference = Some(String::new());
                    p.comments.push(mc);
                }
                l.push = true;
                out.extend(comment_coin(vault, s, id, &r));
            }
            Some(w) => {
                let paid = crate::coins::moved(vault, "spend", 1, &format!("{CMT}{r}"), Some(w), Some(&format!("post:{id}")));
                let word = Word { id: Some(id.into()), at: Some(c.at), tx: Some(c.text.clone()), bn: Some(c.by.clone()), bg: Some(c.glyph.clone()),
                                  cid: Some(c.id.clone()), fc: c.fc.clone(), hh: c.h.clone(), pv: c.pv.clone(), c: paid.then_some(1),
                                  r: paid.then(|| r.clone()), ..Word::of("cmt") };
                if let Some(p) = s.pages.get_mut(w).and_then(|pg| pg.posts.iter_mut().find(|p| p.id == id)) {
                    let mut said = c.clone();
                    said.m = Some(true);
                    p.comments.push(said);
                    p.comment_count += 1;
                }
                ask_in(l, w);
                out.push((w.to_string(), word));
            }
        }
        save(vault, s);
        out
    })
}

/// ONE COIN A COMMENT BROUGHT TO A POST OF MY WALL (iOS commentCoin): four of every five burn and the fifth goes to the post's writer
/// -- the owner keeps their own, a link of the wall's chain; the count lives on the post (cc).
fn comment_coin(vault: &Vault, s: &mut Store, id: &str, r: &str) -> Option<(String, Word)> {
    let p = s.mine.iter_mut().find(|p| p.id == id)?;
    let n = p.cc.unwrap_or(0) + 1;
    p.cc = Some(n);
    let writer = p.author.clone();
    let pay = format!("{CMT_PAY}{r}");
    if n % FIFTH != 0 {
        crate::coins::moved(vault, "burn", 1, &format!("{CMT_BURN}{r}"), None, None);
        return None;
    }
    if writer.is_empty() {
        crate::coins::note(vault, "wall", "keep", 1, &pay);
        return None;
    }
    if !crate::coins::moved(vault, "spend", 1, &pay, Some(&writer), Some(&format!("post:{id}"))) {
        return None;
    }
    crate::coins::note(vault, "wall", "pay", 1, &pay);
    Some((writer, Word { id: Some(id.into()), c: Some(1), r: Some(r.into()), ..Word::of("cpay") }))
}

/// Whether coins may be given on this post of another's wall (iOS MTBoard.coin's guard): a post seen on a person's wall, not mine.
pub fn coin_due(vault: &Vault, wall: &str, id: &str, coins: i64) -> bool {
    coins > 0 && !wall.starts_with("grp:")
        && with(vault, |_, s| s.pages.get(wall).and_then(|pg| pg.posts.iter().find(|p| p.id == id)).map(|p| !p.mine)).unwrap_or(false)
}
/// COINS ON ANOTHER'S POST ARE A SEND OF THE CHAIN (iOS 2304 MTBoard.coin, the author's words 23.10.2026 03:27 and 03:37 MSK): the
/// coins left by the pair's SEND of version 3 under the post's name, and the wall's word only names that SEND.
pub fn coin_sent(id: &str, tx: &str) -> Word {
    Word { id: Some(id.into()), sd: Some(tx.into()), ..Word::of("coin") }
}

/// COINS ON ANOTHER'S POST BY THE BOOK (iOS before 2301, the author's word 03.10 13:40): the book pays first -- a short balance
/// refuses and nothing leaves -- then the wall's word carries the coins to its owner, as a like travels. Only when no coin key is
/// in hand.
pub fn coin(vault: &Vault, wall: &str, id: &str, coins: i64) -> Option<(String, Word)> {
    if !coin_due(vault, wall, id, coins) {
        return None;
    }
    let r = fresh_id();
    if !crate::coins::moved(vault, "spend", coins, &r, Some(wall), Some(&format!("post:{id}"))) {
        return None;
    }
    Some((wall.to_string(), Word { id: Some(id.into()), c: Some(coins), r: Some(r), ..Word::of("coin") }))
}

/// SAVE (iOS keep): the post's files are here (the window fetched them first), and from now on this machine is one of its peers --
/// the wall's owner is told it keeps the post; on my own wall my own mark.
pub fn keep(vault: &Vault, wall: Option<&str>, id: &str) -> Option<(String, Word)> {
    with(vault, |l, s| {
        let out = match wall {
            None => {
                let p = s.mine.iter_mut().find(|p| p.id == id)?;
                toggle(&mut p.keepers, "", true);
                l.push = true;
                None
            }
            Some(w) => {
                let p = s.pages.get_mut(w)?.posts.iter_mut().find(|p| p.id == id)?;
                if s.kept.contains_key(id) {
                    return None;
                }
                let mine = p.mine;
                if !mine && !p.kept {
                    p.kept = true;
                    p.keepers += 1;
                }
                let post = p.clone();
                s.kept.insert(id.into(), Kept { post, wall: w.into(), dl: false });
                (!mine).then(|| (w.to_string(), Word { id: Some(id.into()), on: Some(true), ..Word::of("keep") }))
            }
        };
        save(vault, s);
        out
    })
}

/// «Remove from saved» (iOS unkeep): the owner is told this machine keeps the post no more; the writer keeps their own while it stands.
pub fn unkeep(vault: &Vault, wall: Option<&str>, id: &str) -> Option<(String, Word)> {
    with(vault, |l, s| {
        let out = match wall {
            None => {
                let p = s.mine.iter_mut().find(|p| p.id == id)?;
                toggle(&mut p.keepers, "", false);
                l.push = true;
                None
            }
            Some(w) => {
                let p = s.pages.get_mut(w)?.posts.iter_mut().find(|p| p.id == id)?;
                if p.mine {
                    return None;
                }
                if p.kept {
                    p.kept = false;
                    p.keepers = (p.keepers - 1).max(0);
                }
                s.kept.remove(id);
                Some((w.to_string(), Word { id: Some(id.into()), on: Some(false), ..Word::of("keep") }))
            }
        };
        save(vault, s);
        out
    })
}

/// A DOWNLOAD IS COUNTED ONCE PER PERSON (iOS noteDownloaded): when every file of a post came to this machine by a touch -- on its
/// owner's wall, and on this page at once.
pub fn downloaded(vault: &Vault, wall: Option<&str>, id: &str) -> Option<(String, Word)> {
    with(vault, |l, s| {
        let out = match wall {
            None => {
                let p = s.mine.iter_mut().find(|p| p.id == id)?;
                if p.downloads.iter().any(|x| x.is_empty()) {
                    return None;
                }
                toggle(&mut p.downloads, "", true);
                l.push = true;
                None
            }
            Some(w) => {
                let k = s.kept.get_mut(id)?;
                if k.dl || k.post.mine {
                    return None;
                }
                k.dl = true;
                if let Some(p) = s.pages.get_mut(w).and_then(|pg| pg.posts.iter_mut().find(|p| p.id == id)) {
                    p.downloads += 1;
                }
                Some((w.to_string(), Word { id: Some(id.into()), ..Word::of("dl") }))
            }
        };
        save(vault, s);
        out
    })
}

/// REPOST (iOS repost): the post kept here (its files fetched by the window first) and standing on my own wall too, named by the wall
/// it came from; the wall is told.
pub fn repost(vault: &Vault, wall: &str, id: &str, wall_name: &str) -> Option<(String, Word)> {
    with(vault, |l, s| {
        let p = s.pages.get_mut(wall)?.posts.iter_mut().find(|p| p.id == id)?;
        if p.mine || p.reposted || s.mine.iter().any(|m| m.id == id) {
            return None;
        }
        p.reposted = true;
        p.reposts += 1;
        let q = p.clone();
        s.kept.entry(id.into()).or_insert_with(|| Kept { post: q.clone(), wall: wall.into(), dl: false });
        // THE REPOST KNOWS WHERE IT CAME FROM (iOS repost): the wall, and its writer when the post was that wall owner's own ("" -- mine)
        let by = if q.own == Some(true) { Some(wall.to_string()) } else if q.mine { Some(String::new()) } else { None };
        s.mine.push(Post {
            id: id.into(), author: String::new(), by_name: q.by_name.clone(), by_glyph: q.by_glyph.clone(), at: now_s(), text: q.text.clone(),
            media: q.media.clone(), keepers: vec![String::new()], from: Some(wall_name.chars().take(64).collect()), face: q.face.clone(),
            lp: q.lp.clone(), src: Some(wall.into()), src_by: by, ..Default::default()
        });
        number_missing(&mut s.mine);
        l.push = true;
        save(vault, s);
        Some((wall.to_string(), Word { id: Some(id.into()), ..Word::of("rp") }))
    })
}

/// THE WORDS OF MY OWN POST, CHANGED (iOS edit, the author's word 30.09): only on my own wall and only the words, never a repost's;
/// the wall's next page carries them (the version moves by «ed»). The card of a link the words no longer hold leaves. True when
/// they changed.
pub fn edit(vault: &Vault, id: &str, words: &str) -> bool {
    let t: String = words.trim().chars().take(TEXT_LIMIT).collect();
    with(vault, |l, s| {
        let Some(p) = s.mine.iter_mut().find(|p| p.id == id && p.author.is_empty() && p.from.is_none()) else { return false };
        if t == p.text || (t.is_empty() && p.media.is_empty()) {
            return false;
        }
        let had = p.lp.as_deref().and_then(crate::linkcard::parse).and_then(|c| c["u"].as_str().map(str::to_string));
        if had.is_some_and(|u| !crate::linkcard::urls(&t).contains(&u)) {
            p.lp = None;
        }
        p.text = t;
        p.ed = Some(now_s());
        l.push = true;
        save(vault, s);
        true
    })
}

/// OFF MY WALL, BY ITS OWNER ALONE (iOS remove): the post leaves my wall and its writer is told they need not keep it for me.
pub fn remove(vault: &Vault, id: &str) -> Option<(String, Word)> {
    with(vault, |l, s| {
        let i = s.mine.iter().position(|p| p.id == id)?;
        let p = s.mine.remove(i);
        l.push = true;
        save(vault, s);
        (!p.author.is_empty()).then(|| (p.author, Word { id: Some(id.into()), ..Word::of("drop") }))
    })
}

/// A post of my wall pinned or let go (iOS pin).
pub fn pin(vault: &Vault, id: &str) {
    with(vault, |l, s| {
        if let Some(p) = s.mine.iter_mut().find(|p| p.id == id) {
            p.pinned = !p.pinned;
            l.push = true;
            save(vault, s);
        }
    });
}

/// THE WALL'S MINTING ON THE WALLET (iOS MTBoard.window / wallWindows, the author's word 02.10): every post of my wall and of the
/// walls this machine holds whose comments run unbroken -- no silence of a minute between two of them -- holds a right to a share
/// of its minutes; a run whose last comment is younger than a minute mints now. The rights stand beside the balance and are never
/// added into it: only the core turns a right into a note. (the share in minutes, open)
pub fn wall_windows(vault: &Vault) -> Vec<(i64, bool)> {
    const SILENCE: f64 = 60.0;
    with(vault, |_, s| {
        let mut seen = HashSet::new();
        let mut out = vec![];
        let mine = s.mine.iter().map(|p| (p.id.clone(), p.comments.iter().map(|c| c.at).collect::<Vec<f64>>()));
        let pages = s.pages.values().flat_map(|pg| pg.posts.iter().map(|p| (p.id.clone(), p.comments.iter().map(|c| c.at).collect::<Vec<f64>>())));
        for (id, mut ats) in mine.chain(pages) {
            if ats.is_empty() || !seen.insert(id) {
                continue;
            }
            ats.sort_by(|a, b| a.total_cmp(b));
            let broken = ats.windows(2).any(|w| w[1] - w[0] >= SILENCE);
            let (first, last) = (ats[0], ats[ats.len() - 1]);
            let live = now_s() - last < SILENCE && !broken;
            let end = if live { now_s() } else { last };
            let minutes = if broken { 0 } else { (((end - first).max(0.0) / SILENCE) as i64).max(1) };
            out.push((minutes, live));
        }
        out
    })
}

/// A COMMENT UNDER A POST OF MY WALL HIDDEN FROM MY VISITORS, OR SHOWN AGAIN (iOS hideComment): its words leave the page they are
/// carried, its seal stays in the chain.
pub fn hide_comment(vault: &Vault, id: &str, cid: &str) -> bool {
    with(vault, |l, s| {
        let Some(c) = s.mine.iter_mut().find(|p| p.id == id).and_then(|p| p.comments.iter_mut().find(|c| c.id == cid)) else { return false };
        c.hid = if c.hid == Some(true) { None } else { Some(true) };
        l.push = true;
        save(vault, s);
        true
    })
}

/// A post drawn on the screen joins its wall's list of the moment; the walk names the list to its wall once (iOS view).
pub fn viewed(vault: &Vault, wall: &str, id: &str) {
    with(vault, |l, s| {
        let key = format!("{wall}#{id}");
        let mine = s.pages.get(wall).and_then(|p| p.posts.iter().find(|q| q.id == id)).is_none_or(|q| q.mine || q.views.is_none());
        if mine || s.viewed.contains(&key) || l.seen_due.get(wall).is_some_and(|v| v.iter().any(|x| x == id)) {
            return;
        }
        l.seen_due.entry(wall.into()).or_default().push(id.into());
    });
}

/// The name a post's file is kept under on this machine (iOS fileName).
pub fn file_name(pid: &str, i: usize, ext: &str) -> String {
    format!("wall_{pid}_{i}.{ext}")
}

/// Every file name of the walls this machine keeps -- mine and the pages of others (iOS MTDiskUse: «Pictures of walls»).
pub fn file_names(vault: &Vault) -> HashSet<String> {
    with(vault, |_, s| {
        let mine = s.mine.iter().flat_map(|p| p.media.iter().enumerate().map(move |(i, m)| file_name(&p.id, i, &m.ext)));
        let theirs = s.pages.values().flat_map(|w| w.posts.iter()).flat_map(|p| p.media.iter().enumerate().map(move |(i, m)| file_name(&p.id, i, &m.ext)));
        mine.chain(theirs).collect()
    })
}

/// A mark of the wall as it stands: the window is told when it moved.
pub fn stamp_of(vault: &Vault) -> String {
    with(vault, |_, s| {
        let n: usize = s.pages.values().map(|p| p.posts.iter().map(|q| q.comments.len() + q.likes as usize + 1).sum::<usize>()).sum();
        format!("{}/{}/{}/{}", s.mine.len(), s.mine.iter().map(|p| p.comments.len() + p.likes.len()).sum::<usize>(), s.pages.len(), n)
    })
}

/// The rules as the window shows them, and set.
pub fn rules(vault: &Vault) -> (Rule, Rule) {
    with(vault, |_, s| (s.write.clone(), s.see.clone()))
}
pub fn set_rule(vault: &Vault, act: &str, r: Rule) {
    with(vault, |l, s| {
        if act == "see" { s.see = r } else { s.write = r }
        l.push = true;
        save(vault, s);
    });
}

/// A word of the wall off the wire, parsed; None -- not ours or not readable (buried in silence).
pub fn parse(text: &str) -> Option<Word> {
    serde_json::from_str(text.strip_prefix(MARK)?).ok()
}

/// A word of the wall as it rides.
pub fn letter(w: &Word) -> String {
    format!("{MARK}{}", serde_json::to_string(w).unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vault() -> (Vault, std::path::PathBuf) {
        let dir = std::env::temp_dir().join(format!("mt-board-{}", fresh_id()));
        (Vault::at(&dir).unwrap(), dir)
    }

    #[test]
    fn the_gematria_counts_the_base_29_digits_as_primes_and_a_letter_wears_its_seal() {
        // 28 is one digit, 28 → 109; 29 is «10» → 2 + 3; 255 = 8·29 + 23 → 89 + 23; nothing at all is one zero → 2
        assert_eq!(gematria("1c"), 109);
        assert_eq!(gematria("1d"), 5);
        assert_eq!(gematria("FF"), 112);
        assert_eq!(gematria(&"0".repeat(64)), 2);
        assert_eq!(gematria("xyz"), 0);
        let mid = "t1791303000000-0F6C1D5E-3A2B-4C1D-9E8F-112233445566";
        let (head, g) = letter_mark(mid).expect("a wire name wears a seal");
        let h = crate::wire::hex(&crate::wire::sha(&[format!("montana-letter-seal\nmid:{mid}").as_bytes()]));
        assert_eq!(head, h[..8]);
        assert_eq!(g, gematria(&h));
        assert_eq!((head.as_str(), g), ("5b7c8b1c", 2706), "as a big-number count reads the same seal");
        assert_eq!(letter_mark(&format!("mid:{mid}")), Some((head, g)), "the same name with its prefix");
        assert!(letter_mark("r:archived-row").is_none(), "a row with no wire name wears none");
    }

    #[test]
    fn a_comment_seals_the_one_before_as_ios_does() {
        assert_eq!(stamp(1760943600.5), "2025-10-20T07:00:00.500Z");
        assert_eq!(stamp(0.9996), "1970-01-01T00:00:01.000Z");
        let c = Comment { id: "C1".into(), text: "привет".into(), at: 1760943600.5, pv: None, ..Default::default() };
        let want = crate::wire::hex(&crate::wire::sha(&[format!("C1\n2025-10-20T07:00:00.500Z\n{ZERO}\nпривет").as_bytes()]));
        assert_eq!(seal(&c), want);
        // iOS's word as it writes it: the visitor's counts and marks read back, unknown keys skipped
        let ios = r#"{"t":"page","w":true,"v":"123","ps":[{"id":"P","byName":"Алиса","byGlyph":"А","at":1.5,"text":"т","media":[],"pinned":false,"keepers":1,"likes":2,"downloads":0,"reposts":0,"comments":[{"id":"c","by":"Б","glyph":"Б","text":"к","at":2.0,"o":true,"h":"ab","pv":"00"}],"commentCount":1,"liked":true,"kept":false,"reposted":false,"mine":false,"views":3,"zz":1}]}"#;
        let w = parse(&format!("{MARK}{ios}")).unwrap();
        let p = &w.ps.as_ref().unwrap()[0];
        assert_eq!((p.likes, p.liked, p.views, p.comments[0].o), (2, true, Some(3), Some(true)));
        // a word written here carries no empty field
        let out = letter(&Word { id: Some("X".into()), on: Some(true), ..Word::of("like") });
        assert_eq!(out, format!("{MARK}{{\"t\":\"like\",\"id\":\"X\",\"on\":true}}"));
    }

    #[test]
    fn a_wall_takes_a_post_answers_an_ask_and_its_version_moves() {
        let (v, dir) = vault();
        let names = |_: &str| "Борис".to_string();
        let empty = spoken(&v, "B");
        assert!(empty.is_none(), "an unread wall names no version");
        let _ = posts(&v, None);
        let v0 = spoken(&v, "B").unwrap();
        assert_eq!(v0, wire_tag(b"0w"));
        // B writes a post on my wall: taken, numbered, the version moves, and B is carried the page
        let said = apply(&v, &Word { id: Some("P1".into()), tx: Some("первый".into()), at: Some(1.0), ..Word::of("post") }, "B", &names);
        assert!(said.is_empty());
        let (mine, _, _) = posts(&v, None);
        assert_eq!((mine[0].by_name.as_str(), mine[0].n, mine[0].mine), ("Борис", Some(1), false));
        let v1 = spoken(&v, "B").unwrap();
        assert_ne!(v0, v1);
        let due1 = due(&v, &["B".to_string()]);
        assert_eq!(due1.len(), 1);
        let page = &due1[0].1;
        assert_eq!((page.t.as_str(), page.w, page.v.as_deref()), ("page", Some(true), Some(v1.as_str())));
        assert!(page.ps.as_ref().unwrap()[0].mine, "the visitor's own post is marked theirs");
        page_sent(&v, "B", &v1);
        assert!(due(&v, &["B".to_string()]).is_empty(), "a version carried is not carried twice");
        // B's comment is sealed after the chain; B is answered with the page
        let said = apply(&v, &Word { id: Some("P1".into()), tx: Some("коммент".into()), cid: Some("K".into()), ..Word::of("cmt") }, "B", &names);
        assert_eq!(said[0].1.t, "page");
        let c = &said[0].1.ps.as_ref().unwrap()[0].comments[0];
        assert_eq!((c.m, c.pv.as_deref(), c.reference.is_none()), (Some(true), Some(ZERO), true));
        assert_eq!(c.h.clone().unwrap(), seal(c));
        // the rule of sight leaves B out: B hears what an empty wall says and is carried the empty page once
        set_rule(&v, "see", Rule { rule: "onlyMe".into(), ..Default::default() });
        assert_eq!(spoken(&v, "B").unwrap(), wire_tag(b"0r"));
        let due2 = due(&v, &[]);
        assert_eq!(due2.len(), 1);
        assert!(due2[0].1.ps.as_ref().unwrap().is_empty());
        assert_eq!(apply(&v, &Word { id: Some("P2".into()), tx: Some("x".into()), ..Word::of("post") }, "B", &names)[0].1.t, "no");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_comment_brings_its_coin_four_of_five_burn_and_the_fifth_goes_to_the_post_writer() {
        let (v, dir) = vault();
        let names = |_: &str| "Борис".to_string();
        apply(&v, &Word { id: Some("P1".into()), tx: Some("пост Бориса".into()), at: Some(1.0), ..Word::of("post") }, "B", &names);
        let mut paid = vec![];
        for i in 0..5 {
            let w = Word { id: Some("P1".into()), tx: Some(format!("к{i}")), cid: Some(format!("K{i}")), c: Some(1), r: Some(format!("R{i}")), ..Word::of("cmt") };
            paid.extend(apply(&v, &w, "B", &names).into_iter().filter(|(_, w)| w.t == "cpay"));
        }
        // five coins came, four burned, the fifth paid to the post's writer
        assert_eq!(paid.len(), 1);
        assert_eq!((paid[0].0.as_str(), paid[0].1.c, paid[0].1.r.as_deref()), ("B", Some(1), Some("R4")));
        let (_, counts, _) = crate::coins::state(&v, 50);
        assert_eq!((counts.received, counts.burned, counts.spent), (5, 4, 1));
        // the same gift's name credits once
        let again = Word { id: Some("P1".into()), tx: Some("к0".into()), cid: Some("K9".into()), c: Some(1), r: Some("R0".into()), ..Word::of("cmt") };
        apply(&v, &again, "B", &names);
        assert_eq!(crate::coins::state(&v, 50).1.received, 5);
        // coins on my post from B, credited once by the gift's name
        apply(&v, &Word { id: Some("P1".into()), c: Some(7), r: Some("G1".into()), ..Word::of("coin") }, "B", &names);
        apply(&v, &Word { id: Some("P1".into()), c: Some(7), r: Some("G1".into()), ..Word::of("coin") }, "B", &names);
        assert_eq!(crate::coins::on_target(&v, "post:P1"), 5 + 1 + 7, "every coin moved on the post's row: the comments' five, the fifth paid, the gift");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_saved_post_tells_its_wall_once_and_a_repost_stands_on_my_wall_named_by_its_wall() {
        let (v, dir) = vault();
        let names = |_: &str| String::new();
        let page = Word { w: Some(true), v: Some("1".into()), ps: Some(vec![Seen { id: "Q".into(), by_name: "Кира".into(), text: "мысль".into(), at: 5.0, ..Default::default() }]), ..Word::of("page") };
        apply(&v, &page, "K", &names);
        let (to, w) = keep(&v, Some("K"), "Q").unwrap();
        assert_eq!((to.as_str(), w.t.as_str(), w.on), ("K", "keep", Some(true)));
        assert!(keep(&v, Some("K"), "Q").is_none(), "kept once");
        let (_, d) = downloaded(&v, Some("K"), "Q").unwrap();
        assert_eq!(d.t, "dl");
        assert!(downloaded(&v, Some("K"), "Q").is_none(), "a download counts once a person");
        let (_, rp) = repost(&v, "K", "Q", "Кира").unwrap();
        assert_eq!(rp.t, "rp");
        let (mine, _, _) = posts(&v, None);
        assert_eq!((mine[0].id.as_str(), mine[0].from.as_deref(), mine[0].text.as_str()), ("Q", Some("Кира"), "мысль"));
        assert!(repost(&v, "K", "Q", "Кира").is_none(), "reposted once");
        let (_, u) = unkeep(&v, Some("K"), "Q").unwrap();
        assert_eq!(u.on, Some(false));
        // my own post's words change; a repost's never do
        post_mine(&v, "M1", "Алиса", "было", vec![], None);
        assert!(edit(&v, "M1", "стало"));
        assert!(!edit(&v, "Q", "чужое"));
        assert_eq!(posts(&v, None).0.iter().find(|p| p.id == "M1").unwrap().text, "стало");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_wall_link_names_its_post_long_and_short_as_ios_reads_it() {
        let (v, dir) = vault();
        let names = |_: &str| String::new();
        post_mine(&v, "M1", "Алиса @alice", "первый", vec![], None);
        post_mine(&v, "M2", "Алиса @alice", "второй", vec![], None);
        let q = Seen { id: "Q".into(), by_name: "Кира".into(), n: Some(7), comment_count: 3, at: 5.0,
                       comments: vec![Comment { id: "c2".into(), ..Default::default() }, Comment { id: "c3".into(), ..Default::default() }], ..Default::default() };
        apply(&v, &Word { w: Some(true), v: Some("1".into()), ps: Some(vec![q]), ..Word::of("page") }, "K", &names);
        let name_of = |w: Option<&str>| if w.is_none() { "Алиса @alice".to_string() } else { "Кира @кира".to_string() };
        assert_eq!(target(&v, "montana://wall/post/M1", &name_of), Some((String::new(), "M1".into(), None)));
        assert_eq!(target(&v, "montana://wall/comment/Q/c3", &name_of), Some(("K".into(), "Q".into(), Some("c3".into()))));
        let m2 = posts(&v, None).0.into_iter().find(|p| p.id == "M2").unwrap();
        let link = link_post("Алиса @alice", &m2);
        assert_eq!(link, format!("montana://wall/@alice/{}", m2.n.unwrap()));
        assert_eq!(target(&v, &link, &name_of).map(|t| t.1), Some("M2".to_string()));
        // a name of other letters rides percent-encoded and is read back; the comment's number in the chain names the comment
        let short = format!("montana://wall/{}/7/3", percent_encoded("@кира"));
        assert!(short.contains("%D0%BA"));
        assert_eq!(target(&v, &short, &name_of), Some(("K".into(), "Q".into(), Some("c3".into()))));
        assert_eq!(target(&v, "montana://wall/post/none", &name_of), None, "a post held nowhere here is no target");
        assert_eq!(link_post("Алиса", &m2), "montana://wall/post/M2", "no claimed name: the long link");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_draft_stands_as_its_page_left_it_and_names_the_files_it_lets_go() {
        let (v, dir) = vault();
        let f = |n: &str| DraftFile { file: n.into(), kind: "img".into(), name: "a.jpg".into(), ext: "JPG".into(), size: 3, ..Default::default() };
        assert!(lay_draft(&v, None, Draft { text: "слова".into(), files: vec![f("wd_1"), f("wd_2")], at: 1.0, lp: None }).is_empty());
        let d = draft(&v, None).unwrap();
        assert_eq!((d.files.len(), d.files[0].ext.as_str()), (2, "jpg"));
        assert_eq!(lay_draft(&v, None, Draft { text: "слова".into(), files: vec![f("wd_2")], at: 1.0, lp: None }), vec!["wd_1".to_string()]);
        // a file not of the drafts' own is never taken; nothing written and no file -- no draft, and its last file is let go
        assert_eq!(lay_draft(&v, None, Draft { files: vec![f("x_not_a_draft")], ..Default::default() }), vec!["wd_2".to_string()]);
        assert!(draft(&v, None).is_none());
        lay_draft(&v, Some("K"), Draft { text: "на стене Киры".into(), ..Default::default() });
        assert_eq!(draft(&v, Some("K")).map(|d| d.text), Some("на стене Киры".to_string()));
        assert!(drop_draft(&v, Some("K")).is_empty());
        assert!(draft(&v, Some("K")).is_none());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_writer_and_a_repost_lead_to_their_pages_as_ios_reads_them() {
        let (v, dir) = vault();
        let names = |_: &str| String::new();
        // Kira's own post, and one a third person wrote on her wall
        let page = Word { w: Some(true), v: Some("1".into()), ps: Some(vec![
            Seen { id: "Q".into(), by_name: "Кира".into(), own: Some(true), at: 5.0, ..Default::default() },
            Seen { id: "T".into(), by_name: "Тот".into(), at: 4.0, ..Default::default() },
        ]), ..Word::of("page") };
        apply(&v, &page, "K", &names);
        let ps = posts(&v, Some("K")).0;
        assert_eq!(writer(&v, Some("K"), ps.iter().find(|p| p.id == "Q").unwrap()).as_deref(), Some("K"));
        assert_eq!(writer(&v, Some("K"), ps.iter().find(|p| p.id == "T").unwrap()), None, "a writer the wall never named is nobody here");
        // B writes on my wall: B is its writer; my own post is mine
        apply(&v, &Word { id: Some("P1".into()), tx: Some("от Бориса".into()), at: Some(1.0), ..Word::of("post") }, "B", &names);
        post_mine(&v, "M1", "Алиса", "моё", vec![], None);
        let mine = posts(&v, None).0;
        assert_eq!(writer(&v, None, mine.iter().find(|p| p.id == "P1").unwrap()).as_deref(), Some("B"));
        assert_eq!(writer(&v, None, mine.iter().find(|p| p.id == "M1").unwrap()).as_deref(), Some(""));
        // Kira's post reposted: on my wall it wears Kira as its writer and leads to her wall; a visitor is not told it is mine
        repost(&v, "K", "Q", "Кира").unwrap();
        let r = posts(&v, None).0.into_iter().find(|p| p.id == "Q").unwrap();
        assert_eq!((writer(&v, None, &r).as_deref(), source(&v, None, &r).as_deref()), (Some("K"), Some("K")));
        assert_eq!(r.own, Some(false), "a repost of another's post is not the owner's own");
        // on Kira's page her post stands as itself: no source to lead to
        assert_eq!(source(&v, Some("K"), ps.iter().find(|p| p.id == "Q").unwrap()), None);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn another_wall_stands_as_its_page_says_and_my_words_wait_for_it() {
        let (v, dir) = vault();
        let names = |_: &str| String::new();
        let page = Word { w: Some(true), v: Some("9".into()), ps: Some(vec![Seen { id: "Q".into(), by_name: "Кира".into(), at: 5.0, ..Default::default() }]), ..Word::of("page") };
        apply(&v, &page, "K", &names);
        let (ps, can, held) = posts(&v, Some("K"));
        assert_eq!((ps.len(), can, held), (1, true, true));
        heard_version(&v, "K", "9");
        assert!(due(&v, &[]).iter().all(|(_, w)| w.t != "ask"), "the version held is not asked again");
        heard_version(&v, "K", "10");
        assert!(due(&v, &[]).iter().any(|(c, w)| c == "K" && w.t == "ask"));
        // my like and my comment on Kira's post stand at once; her next page without my comment keeps it half an hour
        let (to, w) = like(&v, Some("K"), "Q").unwrap();
        assert_eq!((to.as_str(), w.on), ("K", Some(true)));
        let cw = comment(&v, Some("K"), "Q", "Алиса", "отлично", Some("FACE".into())).remove(0).1;
        assert_eq!((cw.pv.as_deref(), cw.hh.is_some()), (Some(ZERO), true));
        assert_eq!(cw.fc.as_deref(), Some("FACE"), "my small face rides with my comment (iOS commentFace)");
        assert_eq!((cw.c, cw.r.is_some()), (None, false), "an empty balance pays no coin, and the comment goes all the same");
        apply(&v, &page, "K", &names);
        let (ps, _, _) = posts(&v, Some("K"));
        assert_eq!(ps[0].comments.iter().filter(|c| c.m == Some(true)).count(), 1);
        // a page of nothing but my own posts is my wall come back: refused
        post_mine(&v, "M1", "Алиса", "моё", vec![], None);
        let echo = Word { ps: Some(vec![Seen { id: "M1".into(), ..Default::default() }]), ..Word::of("page") };
        apply(&v, &echo, "K", &names);
        assert_eq!(posts(&v, Some("K")).0[0].id, "Q");
        let f = feed(&v, &|_| true);
        assert_eq!(f.len(), 2);
        let _ = std::fs::remove_dir_all(dir);
    }
}
