//! GROUPS (iOS MontanaGroup.swift; Android Groups.kt): a group is a star through its owner's machine. There is no group key
//! and no group box: every group word is an ordinary letter of a pair -- «​​GR:» + JSON -- on a pipe that already
//! exists. The owner holds a pipe to every member and carries each member's word on to the others; a member holds only the
//! owner's pipe. A member's seat is proven by the pipe its word came on at the owner, and a member hears the group only from
//! the owner. Each copy of a word is a letter of its own name; the receipts of the copies move my letter's ladder.

use crate::book::{birth_ms, mint_mid, Msg};
use crate::post::{marks, Desk};
use crate::profile::strip_crown;
use crate::wire;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;

pub const MARK: &str = "\u{200B}\u{200B}GR:";
/// A row of the group's feed that is no letter: someone was added, left, renamed it (iOS MTGroupEvent).
pub const EVENT: &str = "\u{200B}\u{200B}GE:";
const HELD: &str = "groups.held";
const COPIES: &str = "groups.copies";
const WAITING: &str = "groups.wait";
const TWIN_WAITING: &str = "groups.twinWait"; // the other device's copies of words whose group has not stood here yet
const JOINS: &str = "groups.joins"; // the joins asked by a group's link, until a node took them (ten minutes at most)
const VIEWS: &str = "channels.views"; // a channel's eye (iOS MTChannelViews): the seats that showed each post, the numbers told
const VIEWS_BATCH: usize = 200; // posts named in one «vw» or «vc» (iOS viewsBatch)
const POSTS_KEPT: usize = 400; // the newest posts a channel keeps numbers for (iOS postsKept)
const SAID_KEPT: usize = 1000; // the posts a subscriber remembers having told (iOS saidKept)
const PEOPLE: usize = 200; // iOS peopleLimit

#[derive(Serialize, Deserialize, Clone, Default, Debug)]
pub struct Member {
    pub seat: String,
    pub pipe: String,
}

#[derive(Serialize, Deserialize, Clone, Default, Debug)]
pub struct Group {
    pub id: String,
    /// "g" a group, "c" a channel
    #[serde(default)]
    pub kind: String,
    pub title: String,
    #[serde(default)]
    pub about: String,
    /// the pipe to the owner; empty on the owner's own machine
    #[serde(default)]
    pub owner: String,
    /// my seat: "0" the owner's
    #[serde(default)]
    pub me: String,
    /// the members and their pipes (the owner's machine only)
    #[serde(default)]
    pub members: Vec<Member>,
    /// people, the owner included
    #[serde(default)]
    pub count: u32,
    /// the name each seat gave itself in its last word
    #[serde(default)]
    pub names: BTreeMap<String, String>,
    #[serde(default)]
    pub admins: Vec<String>,
    #[serde(default)]
    pub left: bool,
    #[serde(default)]
    pub removed: bool,
    /// seat -> the newest birth it read (iOS readBy)
    #[serde(default)]
    pub read_by: BTreeMap<String, i64>,
    /// the owner: seat -> how far its reading was carried (iOS readSpread)
    #[serde(default)]
    pub read_spread: BTreeMap<String, i64>,
    /// the words heard (ids), against repeats -- 512 kept
    #[serde(default)]
    pub heard: Vec<String>,
    /// the face the last invitation carried (iOS faceTag: its length and its last sixteen signs); the face itself is kept
    /// among the faces under the group's chat
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub face_tag: String,
    /// a channel's posts are signed by their writer (iOS signs, «sg»: 1)
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub signs: bool,
    /// a channel's posts take no reactions (iOS reacts false, «rx»: 0)
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub reacts_off: bool,
    /// the owner: the standing mark of the group's link (iOS invite, 32 hex); empty -- no link was handed out
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub invite: String,
    /// the owner: the pipes taken out, which the link does not bring back (iOS banned)
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub banned: Vec<String>,
    /// the administrators' rights the owner left out, and their own titles (iOS adminTaken «ax», ranks «rk»)
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub admin_taken: BTreeMap<String, Vec<String>>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub ranks: BTreeMap<String, String>,
    /// what the members may not do, and the slow mode's seconds (iOS barred «bn», slow «sw»)
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub barred: Vec<String>,
    #[serde(default, skip_serializing_if = "is_zero")]
    pub slow: u32,
    /// a channel's subscribers comment under its posts (iOS talks, «dc»: 1), and the reactions it takes (iOS reactList «rl»;
    /// empty -- every one)
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub talks: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub react_list: Vec<String>,
    /// a member: the birth of the newest invitation or taking-out of the owner's applied here -- a copy said again by the
    /// walks may come after a newer one, and an older state never overwrites a newer
    #[serde(default)]
    pub said_at: i64,
    /// the owner: one added reads the group's newest words (iOS history, «Chat History For New Members»: Visible)
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub history: bool,
    /// the owner: the link asks it first (iOS approval, «Request Admin Approval»), and who waits (iOS requests, the newest last)
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub approval: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub requests: Vec<Request>,
    /// an administrator who invites: the group's link as its owner handed it (iOS link, «lk»)
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub link: String,
}

/// One who asked by the link and waits for the owner (iOS MTGroupRequest).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Request {
    pub pipe: String,
    pub name: String,
    pub at: i64,
}

const COMMENTS: &str = "channels.comments"; // chat -> post -> its comments, in the order of their moments (iOS MTChannelComments)
const COMMENT_LIMIT: usize = 4096;
const COMMENT_GAP_MS: i64 = 30_000; // one comment from a seat in thirty seconds (iOS commentGap)
static COMMENT_AT: std::sync::Mutex<Option<BTreeMap<String, i64>>> = std::sync::Mutex::new(None);

/// One comment under a channel's post (iOS MTChannelComment).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Comment {
    pub id: String,
    pub seat: String,
    pub name: String,
    pub text: String,
    pub at: i64,
    pub mine: bool,
}

type Comments = BTreeMap<String, BTreeMap<String, Vec<Comment>>>;

/// The comments a channel keeps: each post's by its name.
pub fn comments_of(vault: &crate::vault::Vault, chat: &str) -> BTreeMap<String, Vec<Comment>> {
    let all: Comments = vault.get(COMMENTS).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    all.get(chat).cloned().unwrap_or_default()
}

/// A comment kept once by its name, in the order of its moment, 500 a post, 300 posts (iOS put). False when it was here.
fn put_comment(vault: &crate::vault::Vault, chat: &str, post: &str, c: Comment) -> bool {
    let mut all: Comments = vault.get(COMMENTS).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    let page = all.entry(chat.to_string()).or_default();
    let list = page.entry(post.to_string()).or_default();
    if list.iter().any(|x| x.id == c.id) {
        return false;
    }
    list.push(c);
    list.sort_by_key(|x| x.at);
    let over = list.len().saturating_sub(500);
    list.drain(..over);
    while page.len() > 300 {
        let first = page.keys().next().cloned().unwrap();
        page.remove(&first);
    }
    serde_json::to_vec(&all).is_ok_and(|b| vault.set(COMMENTS, &b))
}

/// A list of reactions as it came (iOS reactionList): glyphs alone, each once, eighty at most; empty for every one.
fn reaction_list(v: &Value) -> Vec<String> {
    let mut out: Vec<String> = vec![];
    for e in v.as_array().into_iter().flatten().filter_map(|x| x.as_str()) {
        if !e.is_empty() && e.chars().count() <= 4 && !out.iter().any(|x| x == e) && out.len() < 80 {
            out.push(e.to_string());
        }
    }
    out
}

fn is_zero(n: &u32) -> bool {
    *n == 0
}

/// WHAT MEMBERS OF A GROUP MAY DO (iOS MTGroupRight), each a short word on the wire: words, photos, videos, stickers, music,
/// files, voices, round videos, links, reactions, pins, the group's profile.
pub const RIGHTS: [&str; 12] = ["tx", "ph", "vd", "gf", "mu", "fl", "vo", "rv", "ln", "re", "pn", "ci"];
/// WHAT AN ADMINISTRATOR MAY DO (iOS MTAdminRight; a channel's MTChannelRight adds «po», posting).
pub const ADMIN_RIGHTS: [&str; 6] = ["ci", "dm", "bu", "il", "pm", "po"];

/// Whether a seat holds an administrator's right (iOS adminCan): the owner every one; an administrator the ones not left out.
pub fn admin_can(g: &Group, seat: &str, r: &str) -> bool {
    seat == "0" || (g.admins.iter().any(|a| a == seat) && !g.admin_taken.get(seat).is_some_and(|t| t.iter().any(|x| x == r)))
}

/// The rights a word asks of its speaker (iOS rightsAsked): a reaction, a pin, a sticker, a file by its kind, words -- and «links»
/// where they carry one. A deletion of one's own asks none.
pub fn rights_asked(words: &str) -> Vec<&'static str> {
    let links = |t: &str| !crate::linkcard::urls(t).is_empty();
    if words.starts_with(marks::REACT) {
        return vec!["re"];
    }
    if words.starts_with(marks::PIN) {
        return vec!["pn"];
    }
    if words.starts_with(marks::DELETE) {
        return vec![];
    }
    if words.starts_with(marks::STICKER) {
        return vec!["gf"];
    }
    if words.starts_with(marks::VOICE) {
        return vec!["vo"];
    }
    if let Some(j) = words.strip_prefix(marks::MEDIA) {
        let o: Value = serde_json::from_str(j).unwrap_or_default();
        let name = o["n"].as_str().unwrap_or("").to_lowercase();
        let ext = name.rsplit('.').next().unwrap_or("");
        let right = match o["k"].as_str().unwrap_or("") {
            "img" => "ph",
            "vid" | "video" => if o["r"].as_bool() == Some(true) { "rv" } else { "vd" },
            "aud" => "vo",
            _ if ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"].contains(&ext) => "mu",
            _ if ext == "gif" => "gf",
            _ => "fl",
        };
        let mut out = vec![right];
        if links(o["cap"].as_str().unwrap_or("")) {
            out.push("ln");
        }
        return out;
    }
    let text = match words.strip_prefix(marks::EDIT) {
        Some(j) => serde_json::from_str::<Value>(j).ok().and_then(|o| o["tx"].as_str().map(str::to_string)).unwrap_or_default(),
        None => words.to_string(),
    };
    if links(&text) { vec!["tx", "ln"] } else { vec!["tx"] }
}

/// Whether a seat may say these words into the group (iOS allows): the owner and its administrators always; a member by the
/// rights left them.
pub fn allows(g: &Group, seat: &str, words: &str) -> bool {
    seat == "0" || g.admins.iter().any(|a| a == seat) || !rights_asked(words).iter().any(|r| g.barred.iter().any(|b| b == r))
}

/// Whether a seat pins a letter of the group for everyone (iOS pins).
pub fn pins(g: &Group, seat: &str) -> bool {
    g.kind == "g" && (admin_can(g, seat, "pm") || !g.barred.iter().any(|b| b == "pn"))
}

/// A LETTER THAT NAMES ME (iOS mentionsMe): «@» and the name I go by, ending where a word ends -- «@Al» is no mention of «Al»
/// inside «@Alex». It rings even in a chat whose sound is off.
pub fn mentions_me(words: &str, me: &str) -> bool {
    let me = me.trim().to_lowercase();
    if me.is_empty() {
        return false;
    }
    let low = words.to_lowercase();
    let want = format!("@{me}");
    let mut from = 0;
    while let Some(at) = low[from..].find(&want) {
        let end = from + at + want.len();
        if low[end..].chars().next().is_none_or(|c| !c.is_alphanumeric()) {
            return true;
        }
        from = end;
    }
    false
}

/// The moment the owner last took a member's letter while slow mode stands, by group and seat (iOS slowAt).
static SLOW_AT: std::sync::Mutex<Option<BTreeMap<String, i64>>> = std::sync::Mutex::new(None);

/// A member's letter in slow mode (iOS paceSlow): taken once an interval; a letter before it waits and knocks again.
fn pace_slow(g: &Group, seat: &str) -> bool {
    if g.slow == 0 || seat == "0" || g.admins.iter().any(|a| a == seat) {
        return true;
    }
    let mut at = SLOW_AT.lock().unwrap();
    let at = at.get_or_insert_with(BTreeMap::new);
    let k = format!("{}/{seat}", g.id);
    let now = wire::now_ms();
    if now - at.get(&k).copied().unwrap_or(0) < g.slow as i64 * 1000 {
        return false;
    }
    at.insert(k, now);
    true
}

/// The owner's word about its administrators and rights, as it stands (iOS takeAdmins + invited): known rights alone, titles
/// of sixteen signs, a slow mode of an hour at most.
fn take_rights(o: &Value, g: &mut Group) {
    // the link, to an administrator who may invite (iOS «lk»)
    g.link = if g.admins.contains(&g.me) && admin_can(g, &g.me, "il") {
        o["lk"].as_str().filter(|l| l.len() <= 2048 && l.starts_with("https://")).unwrap_or("").to_string()
    } else {
        String::new()
    };
    g.talks = g.kind == "c" && o["dc"] == json!(1);
    g.react_list = if g.kind == "c" { reaction_list(&o["rl"]) } else { vec![] };
    g.admin_taken = o["ax"].as_object().map(|m| m.iter().filter(|(s, _)| is_seat(s)).filter_map(|(s, v)| {
        let known: Vec<String> = v.as_array()?.iter().filter_map(|x| x.as_str()).filter(|x| ADMIN_RIGHTS.contains(x)).map(str::to_string).collect();
        (!known.is_empty()).then(|| (s.clone(), known))
    }).collect()).unwrap_or_default();
    g.ranks = o["rk"].as_object().map(|m| m.iter().filter(|(s, _)| is_seat(s)).filter_map(|(s, v)| {
        let t: String = v.as_str()?.trim().chars().take(16).collect();
        (!t.is_empty()).then(|| (s.clone(), t))
    }).collect()).unwrap_or_default();
    g.barred = o["bn"].as_array().map(|a| a.iter().filter_map(|x| x.as_str()).filter(|x| RIGHTS.contains(x)).map(str::to_string).collect()).unwrap_or_default();
    g.slow = o["sw"].as_u64().filter(|s| *s > 0).map_or(0, |s| s.min(3600) as u32);
}

/// A group's mark in a link (iOS joinMark): «jg=<group>.<mark>», both 32 lowercase hex.
pub fn join_mark(link: &str) -> Option<(String, String)> {
    let q = link.split_once('?')?.1.split('#').next()?;
    let v = q.split('&').find_map(|kv| kv.strip_prefix("jg="))?;
    let (g, m) = v.split_once('.')?;
    let mark = |s: &str| s.len() == 32 && s.chars().all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c));
    (mark(g) && mark(m)).then(|| (g.to_string(), m.to_string()))
}

/// A channel's eye (iOS MTChannelViews.Book): the owner's seats that showed each post, a subscriber's numbers its owner told and
/// the posts it already told as shown; the posts whose numbers moved since the owner last told them.
#[derive(Serialize, Deserialize, Default)]
struct Views {
    #[serde(default)]
    seen: BTreeMap<String, BTreeMap<String, Vec<String>>>,
    #[serde(default)]
    told: BTreeMap<String, BTreeMap<String, u32>>,
    #[serde(default)]
    said: BTreeMap<String, Vec<String>>,
    #[serde(default)]
    moved: BTreeMap<String, Vec<String>>,
}

/// The newest posts kept (a letter's name begins with its birth moment).
fn trimmed<V>(page: &mut BTreeMap<String, V>) {
    while page.len() > POSTS_KEPT {
        let first = page.keys().next().cloned().unwrap();
        page.remove(&first);
    }
}

/// The numbers under a channel's posts (iOS MTChannelViews.views): on the owner's machine one -- its author -- and every seat
/// that showed it; on a subscriber's, what the owner told.
pub fn views_of(vault: &crate::vault::Vault, chat: &str, owner: bool) -> BTreeMap<String, u32> {
    let v: Views = vault.get(VIEWS).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    if owner {
        v.seen.get(chat).map(|p| p.iter().map(|(l, s)| (l.clone(), 1 + s.len() as u32)).collect()).unwrap_or_default()
    } else {
        v.told.get(chat).cloned().unwrap_or_default()
    }
}

/// One copy of a word on its way (iOS copies): to whom, of which letter, how many copies were made, and its fate.
#[derive(Serialize, Deserialize, Clone, Default, Debug)]
struct Copy {
    g: String,
    #[serde(default)]
    l: String,
    to: String,
    #[serde(default)]
    of: u32,
    #[serde(default)]
    at: i64,
    #[serde(default)]
    done: bool,
}

/// What the receiver did with a group word (iOS verdicts): answered with the pair's receipt, or kept for later, or nothing.
#[derive(PartialEq, Debug)]
pub enum Verdict {
    Held,
    Refused,
    Wait,
    Instant,
}

pub fn chat_of(id: &str) -> String {
    format!("grp:{id}")
}

pub fn is_group(r: &str) -> bool {
    r.starts_with("grp:")
}

fn fresh_id() -> String {
    wire::hex(&crate::crypto::random(16).unwrap_or_default())
}

fn is_seat(s: &str) -> bool {
    (1..=16).contains(&s.len()) && s.chars().all(|c| c.is_ascii_hexdigit())
}

/// A group word as the wire carries it: the mark and its JSON, keys short.
fn word(o: Value) -> String {
    format!("{MARK}{o}")
}

/// THE PAST HANDED TO ONE JUST ADDED (iOS add, G.4): a group whose history is visible gives its newest fifty letters of words,
/// each under its own name, by its own speaker, silent («hs»); a channel its owner's newest ten posts. A letter with a file
/// stays behind: its pieces were laid for the receivers of its day. The words for each newcomer, in their order.
pub fn past_words(g: &Group, msgs: &[crate::book::Msg], fresh: &[String], me: &str) -> Vec<Value> {
    let (limit, posts) = match g.kind.as_str() {
        "c" => (10, true),
        _ if g.history => (50, false),
        _ => return vec![],
    };
    let past: Vec<&crate::book::Msg> = msgs.iter().filter(|m| {
        marks::is_row(&m.text) && !m.text.starts_with(marks::MEDIA) && !marks::is_service(&m.text) && (!posts || m.mine)
    }).collect();
    let mut out = vec![];
    for m in &past[past.len().saturating_sub(limit)..] {
        let seat = if m.mine { g.me.clone() } else { m.from.rsplit('/').next().unwrap_or("").to_string() };
        if !is_seat(&seat) || fresh.contains(&seat) || m.mid.is_empty() || m.mid.len() > 80 {
            continue;
        }
        let name = if seat == g.me { me.trim().to_string() } else { g.names.get(&seat).cloned().unwrap_or_default() };
        let mut o = json!({ "t": "say", "g": g.id, "k": g.kind, "ti": g.title, "id": m.mid, "s": seat, "tx": m.text });
        if !name.is_empty() {
            o["n"] = json!(name);
        }
        if !m.qt.is_empty() {
            o["qt"] = json!(m.qt.chars().take(200).collect::<String>());
        }
        if !posts {
            o["hs"] = json!(1);
        }
        out.push(o);
    }
    out
}

/// Whether a group word rings: a letter and an invitation do, unless silent; everything else is quiet (iOS carry).
pub fn rings(text: &str) -> bool {
    let Some(j) = text.strip_prefix(MARK) else { return false };
    let Ok(o) = serde_json::from_str::<Value>(j) else { return false };
    matches!(o["t"].as_str(), Some("say") | Some("inv")) && o["sl"] != json!(1) && o["hs"] != json!(1)
}

/// A group's face on the wire (iOS faceLimit, faceSide 160, JPEG): at most 24 000 signs of base64.
pub const FACE_LIMIT: usize = 24_000;

/// The face an invitation carries, opened: a JPEG or a PNG within the limit (iOS MTGroup.face).
pub fn face_of(fc: &str) -> Option<Vec<u8>> {
    if fc.len() > FACE_LIMIT {
        return None;
    }
    wire::unb64(fc).filter(|b| b.starts_with(&[0xFF, 0xD8]) || b.starts_with(&[0x89, b'P', b'N', b'G']))
}

/// Which face an invitation carries (iOS faceTag): its length and its last sixteen signs.
fn face_tag(fc: &str) -> String {
    let tail: String = fc.chars().rev().take(16).collect::<Vec<_>>().into_iter().rev().collect();
    format!("{}-{tail}", fc.chars().count())
}

/// The fields the person's tag is made over (iOS MTGroup.tagText): the kind, the letter's name, the seats and the words --
/// what a member could alter to pass another's word off.
fn tag_text(o: &Value) -> String {
    ["t", "id", "me", "s", "ti", "tx"].iter().map(|k| o[*k].as_str().unwrap_or("")).collect::<Vec<_>>().join("\0")
}

/// A group word rides the twin mirror unless it only says «typing» (iOS MTGroup.mirrors).
pub fn mirrors(text: &str) -> bool {
    text.strip_prefix(MARK).and_then(|j| serde_json::from_str::<Value>(j).ok()).is_some_and(|o| o["t"].as_str().is_some_and(|t| t != "ty"))
}

impl Desk<'_> {
    fn held(&self) -> BTreeMap<String, Group> {
        self.vault.get(HELD).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
    }

    fn keep_groups(&self, g: &BTreeMap<String, Group>) {
        if let Ok(b) = serde_json::to_vec(g) {
            self.vault.set(HELD, &b);
        }
    }

    pub fn group(&self, id: &str) -> Option<Group> {
        self.held().remove(id)
    }

    fn edit_group(&self, id: &str, f: impl FnOnce(&mut Group)) -> Option<Group> {
        let mut all = self.held();
        let g = all.get_mut(id)?;
        f(g);
        let out = g.clone();
        self.keep_groups(&all);
        Some(out)
    }

    fn copies(&self) -> BTreeMap<String, Copy> {
        self.vault.get(COPIES).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
    }

    /// ONE COPY (iOS carry): a letter of its own name on the pair's pipe; a letter and an invitation ring.
    fn carry(&self, g: &str, letter: &str, to: &str, of: u32, mut o: Value) -> bool {
        // signed by the person (iOS ownTag): the other devices of the words know the word as their own when a box hands it to them
        if let (Some(key), Some(secret)) = (self.author_key.as_deref(), self.book.secret(to)) {
            o["au"] = json!(wire::author_tag(key, &secret, g, &tag_text(&o)));
        }
        let name = mint_mid();
        let mut c = self.copies();
        let now = wire::now_ms();
        c.retain(|_, x| now - x.at < 30 * 86_400_000);
        c.insert(name.clone(), Copy { g: g.into(), l: letter.into(), to: to.into(), of, at: now, done: false });
        if let Ok(b) = serde_json::to_vec(&c) {
            self.vault.set(COPIES, &b);
        }
        let w = word(o);
        if mirrors(&w) {
            // the copy rides to the person's other devices as the word it is (iOS enqueue): there it is done as it was done here
            self.mirror_note(crate::twin::Word { c: to.into(), m: name.clone(), x: w.clone(), o: Some(1), ..Default::default() });
        }
        // durable as iOS's queue: a copy a node did not take now goes again with the next walks, for a day
        self.word_kept(to, &name, &w)
    }

    /// THE SPREAD (iOS spread): the owner to every member but the speaker, a member to the owner; each copy names the letter.
    fn spread(&self, g: &Group, letter: &str, except: Option<&str>, o: Value) -> bool {
        let to: Vec<String> = if g.owner.is_empty() {
            g.members.iter().filter(|m| Some(m.seat.as_str()) != except).map(|m| m.pipe.clone()).collect()
        } else {
            vec![g.owner.clone()]
        };
        let of = to.len() as u32;
        let mut any = false;
        for p in to {
            any |= self.carry(&g.id, letter, &p, of, o.clone());
        }
        any
    }

    /// A ROOM'S WORD INTO THE GROUP (iOS MTGroup.room): carried like an answer -- to everyone this machine carries to, the owner
    /// passing it on -- and never a row; an invitation (ask) and a handed key go to the seats they name alone, «rg» saying
    /// whether it rings there. The title and the kind ride the word.
    pub fn room_word(&self, gid: &str, text: &str, ask: Option<&[String]>, ring: bool) {
        let Some(g) = self.group(gid).filter(|g| !g.left) else { return };
        if text.len() > 4096 {
            return;
        }
        let mut o = json!({ "t": "room", "g": gid, "k": g.kind, "ti": g.title, "id": mint_mid(), "s": g.me, "tx": text });
        if !self.my_name.trim().is_empty() {
            o["n"] = json!(strip_crown(self.my_name.trim()).chars().take(64).collect::<String>());
        }
        let Some(seats) = ask.filter(|s| !s.is_empty()) else {
            self.spread(&g, "", None, o);
            return;
        };
        let seats: Vec<String> = seats.iter().take(32).cloned().collect();
        o["ts"] = json!(seats);
        o["rg"] = json!(if ring { 1 } else { 0 });
        if g.owner.is_empty() {
            let to: Vec<&Member> = g.members.iter().filter(|m| seats.contains(&m.seat)).collect();
            for m in &to {
                self.carry(gid, "", &m.pipe, to.len() as u32, o.clone());
            }
        } else {
            self.carry(gid, "", &g.owner, 1, o);
        }
    }

    /// A ROOM'S ROW IN THE GROUP'S FEED (iOS MTGroupEvent «call», «ended»): begun, by whom and of what kind; ended, how long it lived.
    #[allow(clippy::too_many_arguments)]
    pub fn room_event(&self, id: &str, e: &str, actor: &str, kind: &str, video: bool, room: &str, secs: i64) {
        if self.group(id).is_some_and(|g| g.kind == "c") {
            return; // a channel's feed holds its posts alone
        }
        let mid = mint_mid();
        let at = birth_ms(&mid).unwrap_or_else(wire::now_ms);
        let mut ev = json!({ "e": e, "g": id, "a": actor, "k": kind, "v": if video { 1 } else { 0 }, "r": room });
        if e == "ended" {
            ev["d"] = json!(secs);
        }
        let text = format!("{EVENT}{ev}");
        self.book.edit(&chat_of(id), |c| c.msgs.push(Msg { mid, text, mine: false, at, ..Default::default() }));
    }

    /// The name a seat of a group is known by on this machine (iOS seatName): the chat's own for a pipe I hold, else the name
    /// its own words gave; empty when none.
    pub fn seat_name(&self, g: &Group, seat: &str) -> String {
        let said = g.names.get(seat).cloned().unwrap_or_default();
        let pipe = if g.owner.is_empty() {
            g.members.iter().find(|m| m.seat == seat).map(|m| m.pipe.clone())
        } else if seat == "0" {
            Some(g.owner.clone())
        } else {
            None
        };
        pipe.and_then(|p| self.book.chat(&p)).map(|c| if c.alias.trim().is_empty() { c.name } else { c.alias })
            .filter(|n| !n.trim().is_empty()).unwrap_or(said)
    }

    /// A row of the group's feed that tells what happened (iOS MTGroupEvent).
    fn event(&self, id: &str, e: &str, actor: &str, people: &[String], title: &str) {
        if self.group(id).is_some_and(|g| g.kind == "c") {
            return; // a channel's feed holds its posts alone (iOS lay: a group's events only)
        }
        let mid = mint_mid();
        let at = birth_ms(&mid).unwrap_or_else(wire::now_ms);
        let text = format!("{EVENT}{}", json!({ "e": e, "g": id, "a": actor, "p": people, "t": title }));
        self.book.edit(&chat_of(id), |c| c.msgs.push(Msg { mid, text, mine: false, at, ..Default::default() }));
    }

    /// THE INVITATIONS (iOS tellAll): to every member, its own seat, the count, the admins, the title; the face to the seats
    /// `only` names (every seat when it names none) -- the rest learn the count without it.
    fn tell_all(&self, g: &Group, face: Option<&str>, only: Option<&[String]>) {
        // the link, to an administrator who may invite, once the owner handed one out (iOS «lk»)
        let link = (g.owner.is_empty() && !g.invite.is_empty() && g.admins.iter().any(|a| admin_can(g, a, "il"))).then(|| self.group_link(&g.id)).flatten();
        for m in &g.members {
            let o = self.invitation(g, m, face.filter(|_| only.is_none_or(|o| o.contains(&m.seat))), link.as_ref());
            self.carry(&g.id, "", &m.pipe, 1, o);
        }
    }

    /// The invitation of one member as the group's road carries it (iOS MTGroup.invitationText): a call of two that grows into
    /// a room hands it to its peer on the call's own road too.
    pub fn invitation_text(&self, gid: &str, seat: &str) -> Option<String> {
        let g = self.group(gid).filter(|g| g.owner.is_empty())?;
        let m = g.members.iter().find(|m| m.seat == seat)?;
        Some(word(self.invitation(&g, m, None, None)))
    }

    fn invitation(&self, g: &Group, m: &Member, face: Option<&str>, link: Option<&String>) -> Value {
        {
            let mut o = json!({ "t": "inv", "g": g.id, "k": g.kind, "ti": g.title, "c": g.count, "me": m.seat });
            if let Some(fc) = face {
                o["fc"] = json!(fc);
            }
            if !self.my_name.trim().is_empty() {
                o["n"] = json!(self.my_name.trim());
            }
            if !g.about.is_empty() {
                o["ds"] = json!(g.about);
            }
            if !g.admins.is_empty() {
                o["ad"] = json!(g.admins);
            }
            if !g.admin_taken.is_empty() {
                o["ax"] = json!(g.admin_taken);
            }
            if !g.ranks.is_empty() {
                o["rk"] = json!(g.ranks);
            }
            if let Some(l) = link.filter(|_| g.admins.contains(&m.seat) && admin_can(g, &m.seat, "il")) {
                o["lk"] = json!(l);
            }
            if g.kind == "g" && !g.barred.is_empty() {
                o["bn"] = json!(g.barred);
            }
            if g.kind == "g" && g.slow > 0 {
                o["sw"] = json!(g.slow);
            }
            if g.kind == "c" && g.signs {
                o["sg"] = json!(1);
            }
            if g.kind == "c" && g.reacts_off {
                o["rx"] = json!(0);
            }
            if g.kind == "c" && g.talks {
                o["dc"] = json!(1);
            }
            if g.kind == "c" && !g.react_list.is_empty() {
                o["rl"] = json!(g.react_list);
            }
            o
        }
    }

    /// The group's face as an invitation carries it: the one kept here under its chat.
    fn face_word(&self, id: &str) -> Option<String> {
        self.faces.get(&chat_of(id)).map(|f| wire::b64(&f)).filter(|b| b.len() <= FACE_LIMIT)
    }

    /// A face for the group, kept here and carried: its tag, the chat's face, and the event row.
    fn keep_face(&self, id: &str, bytes: &[u8], fc: &str) -> bool {
        if !self.faces.put(&chat_of(id), bytes) {
            return false;
        }
        self.edit_group(id, |g| g.face_tag = face_tag(fc));
        self.book.edit(&chat_of(id), |c| c.face_at = wire::now_ms());
        true
    }

    /// THE GROUP'S PHOTO, BY ITS OWNER (iOS renew with a face): a JPEG of 160 pixels the window made, kept and carried to every
    /// member in the invitation; «You changed the group photo».
    pub fn group_face(&self, id: &str, jpeg: &[u8]) -> bool {
        let fc = wire::b64(jpeg);
        let Some(g) = self.group(id).filter(|g| g.owner.is_empty() && !g.left) else { return false };
        if face_of(&fc).is_none() || !self.keep_face(id, jpeg, &fc) {
            return false;
        }
        self.tell_all(&g, Some(&fc), None);
        self.event(id, "face", "0", &[], "");
        true
    }

    /// A NEW GROUP (iOS create): its id, a seat for every chosen correspondence, «You created», an invitation to each.
    pub fn group_create(&self, title: &str, pipes: &[String]) -> Option<String> {
        self.group_make("g", title, "", pipes)
    }

    /// A NEW GROUP OR CHANNEL (iOS create, MontanaChannel's three steps): «c» is a group whose owner alone posts, its
    /// subscribers each chosen among the people this machine writes with; the description rides the invitation.
    pub fn group_make(&self, kind: &str, title: &str, about: &str, pipes: &[String]) -> Option<String> {
        let kind = if kind == "c" { "c" } else { "g" };
        let about: String = about.trim().chars().take(255).collect();
        let title: String = strip_crown(title.trim()).chars().take(64).collect();
        if title.is_empty() {
            return None;
        }
        let id = fresh_id();
        let mut members = vec![];
        for p in pipes.iter().filter(|p| self.book.secret(p).is_some()).take(199) {
            let mut seat = fresh_id()[..8].to_string();
            while members.iter().any(|m: &Member| m.seat == seat) {
                seat = fresh_id()[..8].to_string();
            }
            members.push(Member { seat, pipe: p.clone() });
        }
        let g = Group { id: id.clone(), kind: kind.into(), title: title.clone(), about, me: "0".into(), count: members.len() as u32 + 1, members, ..Default::default() };
        let mut all = self.held();
        all.insert(id.clone(), g.clone());
        self.keep_groups(&all);
        self.book.open(&chat_of(&id), &title, false);
        self.event(&id, "made", "0", &[], &title);
        self.tell_all(&g, None, None);
        Some(chat_of(&id))
    }

    /// The owner adds people (iOS add): seats for them, invitations, «You added».
    pub fn group_add(&self, id: &str, pipes: &[String]) {
        let mut new = vec![];
        let g = self.edit_group(id, |g| {
            for p in pipes {
                if g.members.iter().any(|m| &m.pipe == p) || self.book.secret(p).is_none() {
                    continue;
                }
                let seat = fresh_id()[..8].to_string();
                new.push(seat.clone());
                g.members.push(Member { seat, pipe: p.clone() });
            }
            g.count = g.members.len() as u32 + 1;
        });
        if let Some(g) = g.filter(|g| g.owner.is_empty() && !new.is_empty()) {
            self.tell_all(&g, self.face_word(id).as_deref(), Some(&new));
            self.event(id, "added", "0", &new, "");
            self.tell_event(&g, "added", "0", &new);
            self.hand_past(&g, &new);
        }
    }

    /// The owner removes a member (iOS remove): «out» to them, the rest re-invited, «You removed».
    pub fn group_remove(&self, id: &str, seat: &str) {
        self.group_remove_by(id, seat, "0");
    }

    /// The same by an administrator's hand (iOS remove(by:)): the event names the administrator.
    fn group_remove_by(&self, id: &str, seat: &str, actor: &str) {
        let Some(gone) = self.group(id).and_then(|g| g.members.into_iter().find(|m| m.seat == seat)) else { return };
        let g = self.edit_group(id, |g| {
            g.members.retain(|m| m.seat != seat);
            g.admins.retain(|a| a != seat);
            g.count = g.members.len() as u32 + 1;
            if !g.banned.contains(&gone.pipe) {
                g.banned.push(gone.pipe.clone()); // the link does not bring back one the owner took out (iOS banned)
            }
        });
        self.carry(id, "", &gone.pipe, 1, json!({ "t": "out", "g": id }));
        if let Some(g) = g {
            self.tell_all(&g, None, None);
            self.event(id, "removed", actor, &[seat.to_string()], "");
            self.tell_event(&g, "removed", actor, &[seat.to_string()]);
        }
    }

    /// THE OWNER NAMES OR DISMISSES AN ADMINISTRATOR (iOS setAdmin): the rights left out and the title kept while it is one;
    /// every member hears the list by the invitation's word again.
    pub fn group_set_admin(&self, id: &str, seat: &str, on: bool, taken: &[String], rank: &str) {
        let Some(g) = self.edit_group(id, |g| {
            if !g.owner.is_empty() || !g.members.iter().any(|m| m.seat == seat) {
                return;
            }
            g.admins.retain(|a| a != seat);
            if on {
                g.admins.push(seat.to_string());
                g.admins.sort();
            }
            let left: Vec<String> = ADMIN_RIGHTS.iter().filter(|r| taken.iter().any(|t| t == *r)).map(|r| r.to_string()).collect();
            g.admin_taken.remove(seat);
            g.ranks.remove(seat);
            if on && !left.is_empty() {
                g.admin_taken.insert(seat.to_string(), left);
            }
            let title: String = rank.trim().chars().take(16).collect();
            if on && !title.is_empty() {
                g.ranks.insert(seat.to_string(), title);
            }
        }).filter(|g| g.owner.is_empty()) else { return };
        self.tell_all(&g, None, None);
    }

    /// THE OWNER SETS WHAT THE MEMBERS MAY DO AND THE SLOW MODE (iOS setRights): every member hears it by the invitation.
    pub fn group_set_rights(&self, id: &str, barred: &[String], slow: u32) {
        let list: Vec<String> = RIGHTS.iter().filter(|r| barred.iter().any(|b| b == *r)).map(|r| r.to_string()).collect();
        let slow = slow.min(3600);
        let Some(g) = self.group(id).filter(|g| g.owner.is_empty() && g.kind == "g" && (g.barred != list || g.slow != slow)) else { return };
        if let Some(g) = self.edit_group(&g.id, |g| {
            g.barred = list.clone();
            g.slow = slow;
        }) {
            self.tell_all(&g, None, None);
        }
    }

    /// AN ADMINISTRATOR TAKES A PERSON OUT (iOS kick): the owner's machine carries the group, so the word goes to the owner, who
    /// takes the person out as by its own hand -- never the owner, never another administrator.
    pub fn group_kick(&self, id: &str, seat: &str) {
        let Some(g) = self.group(id).filter(|g| !g.left) else { return };
        if g.owner.is_empty() {
            return self.group_remove(id, seat);
        }
        if admin_can(&g, &g.me, "bu") && seat != "0" && seat != g.me && !g.admins.iter().any(|a| a == seat) {
            self.carry(id, "", &g.owner, 1, json!({ "t": "kk", "g": id, "id": mint_mid(), "s": seat }));
        }
    }

    /// Why this machine may not say these words into the group now (iOS refusal): the right the group took («tx», «ph»…), or
    /// «slow:<seconds left>»; nothing when it may.
    pub fn group_refusal(&self, id: &str, words: &str) -> Option<String> {
        let g = self.group(id).filter(|g| g.kind == "g" && !g.owner.is_empty() && !g.left && !g.admins.contains(&g.me))?;
        if let Some(r) = rights_asked(words).into_iter().find(|r| g.barred.iter().any(|b| b == r)) {
            return Some(r.to_string());
        }
        if g.slow == 0 || !marks::is_row(words) {
            return None;
        }
        let last = self.book.chat(&chat_of(id))?.msgs.iter().filter(|m| m.mine && !m.text.starts_with(EVENT)).map(|m| m.at).max()?;
        let left = g.slow as i64 * 1000 - (wire::now_ms() - last);
        (left > 0).then(|| format!("slow:{}", (left + 999) / 1000))
    }

    /// Leave (a member: «bye» to the owner) or delete for everyone (the owner: «out» with «dl» to each).
    pub fn group_leave(&self, id: &str) {
        let Some(g) = self.group(id) else { return };
        if g.owner.is_empty() {
            for m in &g.members {
                self.carry(id, "", &m.pipe, 1, json!({ "t": "out", "g": id, "dl": 1 }));
            }
        } else if !g.left {
            self.carry(id, "", &g.owner, 1, json!({ "t": "bye", "g": id }));
            self.event(id, "left", &g.me, &[], "");
        }
        self.edit_group(id, |g| g.left = true);
    }

    /// The owner renames (iOS renew): every member hears the new title, «You renamed».
    pub fn group_rename(&self, id: &str, title: &str) {
        let title: String = strip_crown(title.trim()).chars().take(64).collect();
        if title.is_empty() {
            return;
        }
        if let Some(g) = self.edit_group(id, |g| g.title = title.clone()).filter(|g| g.owner.is_empty()) {
            self.book.edit(&chat_of(id), |c| c.name = title.clone());
            self.tell_all(&g, None, None);
            self.event(id, "named", "0", &[], &title);
        }
    }

    /// THE GROUP'S LINK (iOS inviteLink): the owner's own permanent card -- whoever opens it meets the owner, the one road of
    /// a link -- with the group's mark after it; the mark is minted once.
    pub fn group_link(&self, id: &str) -> Option<String> {
        let g = self.group(id).filter(|g| !g.left)?;
        if !g.owner.is_empty() {
            return (!g.link.is_empty()).then(|| g.link.clone()); // an administrator's: the owner's link as it came
        }
        let mark = if g.invite.is_empty() {
            let m = fresh_id();
            self.edit_group(id, |g| g.invite = m.clone());
            m
        } else {
            g.invite
        };
        let card = (crate::card::Card { vault: self.vault }).offer_permanent(&self.my_name)?;
        Some(format!("{card}?jg={id}.{mark}"))
    }

    /// A new mark (iOS resetInvite): every link given before opens nothing more.
    pub fn group_link_reset(&self, id: &str) {
        if let Some(g) = self.edit_group(id, |g| { if g.owner.is_empty() { g.invite = fresh_id(); } }).filter(|g| g.owner.is_empty()) {
            if g.admins.iter().any(|a| admin_can(&g, a, "il")) {
                self.tell_all(&g, None, None); // the administrators who invite hold the new link
            }
        }
    }

    /// THE OWNER TURNS THE LINK'S APPROVAL ON OR OFF (iOS setApproval); the requests already waiting stay until answered.
    pub fn group_set_approval(&self, id: &str, on: bool) {
        self.edit_group(id, |g| { if g.owner.is_empty() { g.approval = on; } });
    }

    /// THE OWNER ADDS ONE WHO ASKED (iOS approve): by its own road, as by the link they joined by.
    pub fn group_approve(&self, id: &str, pipe: &str) -> bool {
        let Some(g) = self.group(id).filter(|g| g.owner.is_empty() && !g.left) else { return false };
        let Some(r) = g.requests.iter().find(|r| r.pipe == pipe).cloned() else { return false };
        self.edit_group(id, |g| g.requests.retain(|x| x.pipe != pipe));
        if g.members.iter().any(|m| m.pipe == pipe) {
            return true;
        }
        self.admit(id, pipe, &r.name, false) == Verdict::Held
    }

    /// THE OWNER DISMISSES ONE WHO ASKED (iOS dismiss): they are told nothing; the link may bring them again.
    pub fn group_dismiss(&self, id: &str, pipe: &str) {
        self.edit_group(id, |g| { if g.owner.is_empty() { g.requests.retain(|x| x.pipe != pipe); } });
    }

    /// ONE THE LINK BROUGHT IS ADDED (iOS add viaLink): a fresh seat, the invitation with the face to them, «joined» to the rest.
    fn admit(&self, gid: &str, pipe: &str, name: &str, quiet: bool) -> Verdict {
        let Some(g) = self.group(gid) else { return Verdict::Refused };
        if g.members.len() >= PEOPLE - 1 {
            return Verdict::Refused;
        }
        let mut seat = fresh_id()[..8].to_string();
        while g.members.iter().any(|m| m.seat == seat) {
            seat = fresh_id()[..8].to_string();
        }
        let Some(g) = self.edit_group(gid, |g| {
            g.members.push(Member { seat: seat.clone(), pipe: pipe.to_string() });
            g.count = g.members.len() as u32 + 1;
            if !name.is_empty() {
                g.names.insert(seat.clone(), name.to_string());
            }
        }) else { return Verdict::Refused };
        self.event(gid, "joined", &seat, &[], "");
        if !quiet {
            self.tell_all(&g, self.face_word(gid).as_deref(), Some(std::slice::from_ref(&seat)));
            let tx = json!({ "e": "joined", "g": gid, "a": seat, "p": [] }).to_string();
            let eid = mint_mid();
            for m in g.members.iter().filter(|m| m.seat != seat) {
                self.carry(gid, "", &m.pipe, 1, json!({ "t": "ev", "g": gid, "id": eid, "s": "0", "tx": tx }));
            }
            self.hand_past(&g, std::slice::from_ref(&seat));
        }
        Verdict::Held
    }

    /// The past carried to the people just added (past_words), each a copy of its own.
    fn hand_past(&self, g: &Group, fresh: &[String]) {
        let Some(c) = self.book.chat(&chat_of(&g.id)) else { return };
        let words = past_words(g, &c.msgs, fresh, &self.my_name);
        for m in g.members.iter().filter(|m| fresh.contains(&m.seat)) {
            for o in &words {
                self.carry(&g.id, "", &m.pipe, 1, o.clone());
            }
        }
    }

    /// THE OWNER SHOWS OR HIDES THE GROUP'S PAST TO NEW MEMBERS (iOS setHistory).
    pub fn group_set_history(&self, id: &str, visible: bool) {
        self.edit_group(id, |g| { if g.owner.is_empty() && g.kind == "g" { g.history = visible; } });
    }

    /// THE JOIN BY A LINK (iOS askJoin): asked of the owner just met, through the pipe the meeting opened -- by the invitation's
    /// own road while the introduction is unanswered; kept and asked again by the walks until a node took it, ten minutes.
    pub fn group_join(&self, pipe: &str, gid: &str, mark: &str) {
        let mut joins: Vec<Value> = self.vault.get(JOINS).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        joins.retain(|j| j["g"] != json!(gid));
        joins.push(json!({ "p": pipe, "g": gid, "k": mark, "at": wire::now_ms() }));
        if let Ok(b) = serde_json::to_vec(&joins) {
            self.vault.set(JOINS, &b);
        }
        self.joins_retry();
    }

    fn joins_retry(&self) {
        let joins: Vec<Value> = self.vault.get(JOINS).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        if joins.is_empty() {
            return;
        }
        let now = wire::now_ms();
        let left: Vec<Value> = joins.into_iter().filter(|j| now - j["at"].as_i64().unwrap_or(0) < 600_000).filter(|j| {
            let (pipe, gid, mark) = (j["p"].as_str().unwrap_or(""), j["g"].as_str().unwrap_or(""), j["k"].as_str().unwrap_or(""));
            !self.ask_join(pipe, gid, mark)
        }).collect();
        if let Ok(b) = serde_json::to_vec(&left) {
            self.vault.set(JOINS, &b);
        }
    }

    fn ask_join(&self, pipe: &str, gid: &str, mark: &str) -> bool {
        let Some(secret) = self.book.secret(pipe) else { return false };
        let mut o = json!({ "t": "jn", "g": gid, "id": mint_mid(), "tx": mark });
        if !self.my_name.trim().is_empty() {
            o["n"] = json!(self.my_name.trim());
        }
        if let Some(key) = self.author_key.as_deref() {
            o["au"] = json!(wire::author_tag(key, &secret, gid, &tag_text(&o)));
        }
        let mid = mint_mid();
        let text = word(o);
        match crate::meeting::first(self.vault, pipe) {
            Some((ct, inv)) => self.knock_first(&secret, &ct, &inv, &mid, &text),
            None => self.deliver(pipe, &mid, &text),
        }
    }

    /// A CHANNEL'S OWN WAYS, BY ITS OWNER (iOS «Sign Messages», «Allow Reactions»): every subscriber hears them in the invitation.
    pub fn channel_set(&self, id: &str, signs: bool, reacts: bool, talks: bool) {
        if let Some(g) = self.edit_group(id, |g| {
            g.signs = signs;
            g.reacts_off = !reacts;
            g.talks = talks;
        }).filter(|g| g.owner.is_empty() && g.kind == "c" && !g.left) {
            self.tell_all(&g, None, None);
        }
    }

    /// THE OWNER CHOOSES THE REACTIONS ITS CHANNEL TAKES (iOS setReactionList, «Some Reactions»): empty -- every one; every
    /// subscriber hears it by the invitation's word again.
    pub fn channel_reactions(&self, id: &str, list: &[String]) {
        let next = reaction_list(&json!(list));
        let Some(g) = self.group(id).filter(|g| g.owner.is_empty() && g.kind == "c" && !g.left && g.react_list != next) else { return };
        if let Some(g) = self.edit_group(&g.id, |g| g.react_list = next.clone()) {
            self.tell_all(&g, None, None);
        }
    }

    /// I TYPE IN A GROUP (iOS MTGroup.typing): an instant word to the pipes this machine holds for the group -- the owner's at
    /// every member, a member's at the owner -- said once, never queued, receipted, mirrored or written; a group's alone, never a
    /// channel's, and only where my words may go. The window keeps the pace (three seconds), the caller the «Online status».
    pub fn group_typing(&self, id: &str) {
        let Some(g) = self.group(id).filter(|g| g.kind == "g" && !g.left && !g.removed && allows(g, &g.me, "")) else { return };
        let mut o = json!({ "t": "ty", "g": id, "s": g.me });
        if !self.my_name.trim().is_empty() {
            o["n"] = json!(self.my_name.trim());
        }
        let to: Vec<String> = if g.owner.is_empty() { g.members.iter().map(|m| m.pipe.clone()).collect() } else { vec![g.owner.clone()] };
        self.throw_typing(&to, &word(o));
    }

    /// A typing word thrown at pipes (iOS throwTyping): once each, sixteen at a time; a blocked person hears none (deliver).
    fn throw_typing(&self, to: &[String], text: &str) {
        for part in to.chunks(16) {
            std::thread::scope(|s| {
                for p in part {
                    s.spawn(move || self.deliver(p, &mint_mid(), text));
                }
            });
        }
    }

    /// A COMMENT OF MINE UNDER A CHANNEL'S POST (iOS comment): kept here at once and carried as the channel's word -- a
    /// subscriber's to the owner, the owner's to everyone; one in thirty seconds from a subscriber. False -- not carried.
    pub fn channel_comment(&self, id: &str, post: &str, text: &str) -> bool {
        let words = text.trim();
        let Some(g) = self.group(id).filter(|g| g.kind == "c" && g.talks && !g.left) else { return false };
        let chat = chat_of(id);
        if words.is_empty() || words.chars().count() > COMMENT_LIMIT || !self.book.chat(&chat).is_some_and(|c| c.msgs.iter().any(|m| m.mid == post)) {
            return false;
        }
        if !g.owner.is_empty() {
            let mut at = COMMENT_AT.lock().unwrap();
            let at = at.get_or_insert_with(BTreeMap::new);
            let k = format!("me/{id}");
            if wire::now_ms() - at.get(&k).copied().unwrap_or(0) < COMMENT_GAP_MS {
                return false;
            }
            at.insert(k, wire::now_ms());
        }
        let cid = mint_mid();
        let me = self.my_name.trim().to_string();
        put_comment(self.vault, &chat, post, Comment { id: cid.clone(), seat: g.me.clone(), name: me.clone(), text: words.into(), at: wire::now_ms(), mine: true });
        let mut o = json!({ "t": "cm", "g": id, "id": cid, "s": g.me, "tx": words, "qm": post });
        if !me.is_empty() {
            o["n"] = json!(me);
        }
        self.spread(&g, "", None, o) || (g.owner.is_empty() && g.members.is_empty())
    }

    /// A SUBSCRIBER'S SCREEN SHOWED POSTS (iOS MTChannelViews.shown + MTGroup.tellSeen): their names go to the owner alone, once
    /// each, for its count; nothing at all while the person keeps their reading to themselves (a read receipt, the critic's K-1).
    pub fn channel_seen(&self, chat: &str) {
        let Some(id) = chat.strip_prefix("grp:") else { return };
        let Some(g) = self.group(id).filter(|g| g.kind == "c" && !g.owner.is_empty() && !g.left) else { return };
        if !self.read_receipts {
            return;
        }
        let mut v: Views = self.vault.get(VIEWS).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        let said = v.said.get(chat).cloned().unwrap_or_default();
        let posts: Vec<String> = self.book.chat(chat).map(|c| c.msgs.into_iter().filter(|m| !m.mine && marks::is_row(&m.text) && !said.contains(&m.mid))
            .map(|m| m.mid).collect()).unwrap_or_default();
        let mut list: Vec<String> = posts.into_iter().take(VIEWS_BATCH).collect();
        if list.is_empty() {
            return;
        }
        list.sort();
        if self.carry(id, "", &g.owner, 1, json!({ "t": "vw", "g": id, "id": mint_mid(), "s": g.me, "tx": list.join(",") })) {
            let said = v.said.entry(chat.to_string()).or_default();
            said.extend(list);
            let over = said.len().saturating_sub(SAID_KEPT);
            said.drain(..over);
            if let Ok(b) = serde_json::to_vec(&v) {
                self.vault.set(VIEWS, &b);
            }
        }
    }

    /// A subscriber's seat showed these posts (their «vw», iOS saw): each seat counted once; the numbers that moved leave to every
    /// subscriber with the next walk, in one word.
    fn channel_saw(&self, id: &str, seat: &str, letters: &[String], tell: bool) {
        let chat = chat_of(id);
        let mut v: Views = self.vault.get(VIEWS).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        let page = v.seen.entry(chat.clone()).or_default();
        let mut grew = vec![];
        for l in letters {
            let seats = page.entry(l.clone()).or_default();
            if !seats.iter().any(|s| s == seat) && seats.len() < PEOPLE {
                seats.push(seat.to_string());
                grew.push(l.clone());
            }
        }
        if grew.is_empty() {
            return;
        }
        trimmed(page);
        if tell {
            let moved = v.moved.entry(chat).or_default();
            for l in grew {
                if !moved.contains(&l) {
                    moved.push(l);
                }
            }
        }
        if let Ok(b) = serde_json::to_vec(&v) {
            self.vault.set(VIEWS, &b);
        }
    }

    /// THE OWNER TELLS THE NUMBERS THAT MOVED (iOS count + tellCounts): one silent word to every subscriber, the newest 200.
    fn channel_counts(&self) {
        let mut v: Views = self.vault.get(VIEWS).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        if v.moved.is_empty() {
            return;
        }
        for (chat, mut letters) in std::mem::take(&mut v.moved) {
            let Some(g) = chat.strip_prefix("grp:").and_then(|id| self.group(id)).filter(|g| g.owner.is_empty() && g.kind == "c") else { continue };
            letters.sort();
            let page = v.seen.get(&chat).cloned().unwrap_or_default();
            let numbers: BTreeMap<String, u32> = letters.iter().rev().take(VIEWS_BATCH).map(|l| (l.clone(), 1 + page.get(l).map_or(0, |s| s.len()) as u32)).collect();
            let tx = serde_json::to_string(&numbers).unwrap_or_default();
            for m in &g.members {
                self.carry(&g.id, "", &m.pipe, 1, json!({ "t": "vc", "g": g.id, "id": mint_mid(), "s": "0", "tx": tx }));
            }
        }
        if let Ok(b) = serde_json::to_vec(&v) {
            self.vault.set(VIEWS, &b);
        }
    }

    /// The owner's numbers, at a subscriber's machine (iOS told): a number only grows, so a word that came late changes nothing.
    fn channel_told(&self, id: &str, numbers: &BTreeMap<String, u32>) {
        let chat = chat_of(id);
        let mut v: Views = self.vault.get(VIEWS).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        let page = v.told.entry(chat).or_default();
        for (l, n) in numbers {
            let held = page.entry(l.clone()).or_insert(0);
            *held = (*held).max((*n).min(PEOPLE as u32 + 1));
        }
        trimmed(page);
        if let Ok(b) = serde_json::to_vec(&v) {
            self.vault.set(VIEWS, &b);
        }
    }

    /// An event to every member but those it is about (iOS tellEvent): its actor's seat as the event names it -- the owner's for
    /// an addition, the leaver's own for a leaving.
    fn tell_event(&self, g: &Group, e: &str, actor: &str, about: &[String]) {
        let people: &[String] = if e == "left" { &[] } else { about };
        let tx = json!({ "e": e, "g": g.id, "a": actor, "p": people }).to_string();
        let id = mint_mid();
        for m in g.members.iter().filter(|m| !about.contains(&m.seat)) {
            self.carry(&g.id, "", &m.pipe, 1, json!({ "t": "ev", "g": g.id, "id": id, "s": "0", "tx": tx }));
        }
    }

    /// A WORD OF MINE INTO A GROUP (the postman's door for «grp:» chats): a letter goes as «say», its answers (reactions,
    /// edits, deletions, pins) as «sig», my reading as «rd»; everything else of a pair (names, faces, receipts) has no place.
    pub fn group_deliver(&self, id: &str, mid: &str, text: &str, qt: &str, qm: &str) -> bool {
        let Some(g) = self.group(id) else { return false };
        // a channel's administrator with «Post Messages» posts through the owner (iOS MTChannelRight.post)
        let subscriber = g.kind == "c" && !g.owner.is_empty() && !(g.admins.contains(&g.me) && admin_can(&g, &g.me, "po"));
        if g.left || subscriber && (!text.starts_with(marks::REACT) || g.reacts_off) {
            return false; // a channel's subscriber only reads, and answers a post where the channel takes reactions
        }
        let name = self.my_name.trim().to_string();
        if let Some(ms) = text.strip_prefix(marks::READ) {
            let ms: i64 = ms.trim().parse().unwrap_or(0);
            if g.owner.is_empty() {
                self.spread_read(&g, "0", ms);
                return true;
            }
            return self.carry(id, "", &g.owner, 1, json!({ "t": "rd", "g": id, "id": mint_mid(), "s": g.me, "tx": ms.to_string() }));
        }
        if marks::is_row(text) {
            let mut o = json!({ "t": "say", "g": id, "k": g.kind, "ti": g.title, "id": mid, "s": g.me, "tx": text });
            if !name.is_empty() {
                o["n"] = json!(name);
            }
            if !qt.is_empty() {
                o["qt"] = json!(qt.chars().take(200).collect::<String>());
                o["qm"] = json!(qm);
            }
            if g.owner.is_empty() && g.members.is_empty() {
                return true; // a group of one: nobody to carry to
            }
            return self.spread(&g, mid, None, o);
        }
        if [marks::REACT, marks::EDIT, marks::DELETE, marks::PIN].iter().any(|m| text.starts_with(m)) {
            let mut o = json!({ "t": "sig", "g": id, "id": mint_mid(), "s": g.me, "tx": text });
            if !name.is_empty() {
                o["n"] = json!(name);
            }
            self.spread(&g, "", None, o);
            return true;
        }
        true // a word of a pair: the group has no place for it
    }

    /// A LETTER'S CARD INTO A GROUP (iOS carryCard): after the letter, as the group's own word «lp» under the letter's name, to
    /// everyone this machine carries to.
    pub fn group_card(&self, id: &str, letter: &str, lp: &str) {
        let Some(g) = self.group(id).filter(|g| !g.left && (g.kind != "c" || g.owner.is_empty())) else { return };
        let Some(card) = crate::linkcard::fitted(lp) else { return };   // the group's word is a long road: the picture rides while it fits
        self.spread(&g, "", None, json!({ "t": "lp", "g": id, "id": letter, "s": g.me, "tx": card }));
    }

    /// THE COPY'S RECEIPT (iOS copyDelivered + follow): my letter is «delivered» once every copy of it was answered.
    pub fn group_receipt(&self, copy: &str) -> bool {
        let mut c = self.copies();
        let Some(x) = c.get_mut(copy) else { return false };
        x.done = true;
        let (g, l) = (x.g.clone(), x.l.clone());
        if let Ok(b) = serde_json::to_vec(&c) {
            self.vault.set(COPIES, &b);
        }
        if !l.is_empty() && c.values().filter(|x| x.g == g && x.l == l).all(|x| x.done) {
            self.book.edit(&chat_of(&g), |c| {
                if let Some(m) = c.msgs.iter_mut().find(|m| m.mine && m.mid == l) {
                    if m.state < 1 {
                        m.advance(1);
                    }
                    m.advance(2);
                }
            });
        }
        true
    }

    /// The reading of one seat carried to the speakers it covers (iOS spreadRead): the owner tells each member whose letters
    /// were read; its own letters it marks itself.
    fn spread_read(&self, g: &Group, reader: &str, ms: i64) {
        let since = g.read_spread.get(reader).copied().unwrap_or(0);
        if ms <= since {
            return;
        }
        self.edit_group(&g.id, |g| { g.read_spread.insert(reader.to_string(), ms); });
        let chat = self.book.chat(&chat_of(&g.id));
        let mut speakers: Vec<String> = vec![];
        let mut mine = false;
        for m in chat.iter().flat_map(|c| c.msgs.iter()).filter(|m| m.at > since && m.at <= ms && !m.text.starts_with(EVENT)) {
            if m.mine {
                mine = true;
            } else if let Some(seat) = m.from.rsplit('/').next().filter(|s| *s != reader && !s.is_empty()) {
                if !speakers.contains(&seat.to_string()) {
                    speakers.push(seat.to_string());
                }
            }
        }
        if mine && reader != "0" {
            self.read_mine(&g.id, reader, ms);
        }
        for seat in speakers {
            if let Some(p) = g.members.iter().find(|m| m.seat == seat) {
                self.carry(&g.id, "", &p.pipe, 1, json!({ "t": "rd", "g": g.id, "id": mint_mid(), "s": reader, "tx": ms.to_string(), "ts": [seat] }));
            }
        }
    }

    fn read_mine(&self, id: &str, reader: &str, ms: i64) {
        self.edit_group(id, |g| {
            let held = g.read_by.entry(reader.to_string()).or_insert(0);
            *held = (*held).max(ms);
        });
        self.book.edit(&chat_of(id), |c| {
            for m in c.msgs.iter_mut().filter(|m| m.mine && m.at <= ms) {
                if m.state < 2 {
                    m.advance(2);
                }
                m.advance(3);
            }
        });
    }

    /// The words kept for later (a letter before its group's invitation) are tried again.
    pub fn group_retry(&self) {
        self.channel_counts();
        self.joins_retry();
        let twins: Vec<(String, String, String)> = self.vault.get(TWIN_WAITING).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        if !twins.is_empty() {
            let left: Vec<_> = twins.into_iter().filter(|(pipe, mid, text)| self.group_handle(pipe, mid, text, true) == Verdict::Wait).collect();
            if let Ok(b) = serde_json::to_vec(&left) {
                self.vault.set(TWIN_WAITING, &b);
            }
        }
        let waiting: Vec<(String, String, String)> = self.vault.get(WAITING).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        if waiting.is_empty() {
            return;
        }
        let mut left = vec![];
        for (pipe, mid, text) in waiting {
            match self.group_handle(&pipe, &mid, &text, false) {
                Verdict::Wait => left.push((pipe, mid, text)),
                Verdict::Held | Verdict::Refused => self.answer_copy(&pipe, &mid),
                Verdict::Instant => {}
            }
        }
        if let Ok(b) = serde_json::to_vec(&left) {
            self.vault.set(WAITING, &b);
        }
    }

    fn answer_copy(&self, pipe: &str, mid: &str) {
        self.deliver(pipe, &format!("rcpt-{mid}"), &format!("{}{mid}", marks::DELIVERED));
    }

    /// A GROUP WORD ON A PIPE (iOS handle): answered with the pair's receipt when held or refused; a word whose group is not
    /// known yet is kept here and tried again, its receipt after.
    pub fn group_word(&self, pipe: &str, mid: &str, text: &str) {
        // THE PERSON'S OWN WORD, HEARD ON A PIPE ITS DEVICES SHARE (iOS ownWord): done here as the hand did it there, never judged
        // as a stranger's, never answered -- the device that spoke carries it
        if let (Some(o), Some(secret)) = (text.strip_prefix(MARK).and_then(|j| serde_json::from_str::<Value>(j).ok()), self.book.secret(pipe)) {
            if let (Some(au), Some(g)) = (o["au"].as_str(), o["g"].as_str()) {
                if wire::author_holds(au, self.author_key.as_deref(), &secret, g, &tag_text(&o)) {
                    self.group_own(pipe, text);
                    return;
                }
            }
        }
        match self.group_handle(pipe, mid, text, false) {
            Verdict::Held | Verdict::Refused => self.answer_copy(pipe, mid),
            Verdict::Wait => {
                let mut w: Vec<(String, String, String)> = self.vault.get(WAITING).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
                if !w.iter().any(|x| x.1 == mid) {
                    w.push((pipe.to_string(), mid.to_string(), text.to_string()));
                    w.truncate(512);
                    if let Ok(b) = serde_json::to_vec(&w) {
                        self.vault.set(WAITING, &b);
                    }
                }
            }
            Verdict::Instant => {}
        }
    }

    /// A correspondent's group word another device of the person took (the twin mirror): done here as there, but carried on to
    /// nobody and answered to nobody -- the device that took it did both.
    pub fn group_heard_by_twin(&self, pipe: &str, mid: &str, text: &str) {
        if self.group_handle(pipe, mid, text, true) == Verdict::Wait {
            let mut w: Vec<(String, String, String)> = self.vault.get(TWIN_WAITING).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
            if !w.iter().any(|x| x.1 == mid) {
                w.push((pipe.to_string(), mid.to_string(), text.to_string()));
                let over = w.len().saturating_sub(512);
                w.drain(..over);
                if let Ok(b) = serde_json::to_vec(&w) {
                    self.vault.set(TWIN_WAITING, &b);
                }
            }
        }
    }

    /// `quiet`: a copy the twin mirror brought -- applied, never carried on or answered.
    fn group_handle(&self, pipe: &str, copy: &str, text: &str, quiet: bool) -> Verdict {
        let Some(o) = text.strip_prefix(MARK).and_then(|j| serde_json::from_str::<Value>(j).ok()) else { return Verdict::Refused };
        let (Some(t), Some(gid)) = (o["t"].as_str(), o["g"].as_str()) else { return Verdict::Refused };
        if gid.len() != 32 || !gid.chars().all(|c| c.is_ascii_hexdigit()) {
            return Verdict::Refused;
        }
        let name: String = o["n"].as_str().map(|n| strip_crown(n.trim()).chars().take(64).collect()).unwrap_or_default();
        let g = self.group(gid);
        // the seat a word speaks for: at the owner, the pipe it came on; at a member, the word's own «s» from the owner's pipe
        let seat_of = |g: &Group| -> Option<String> {
            if g.owner.is_empty() {
                g.members.iter().find(|m| m.pipe == pipe).map(|m| m.seat.clone())
            } else if g.owner == pipe {
                o["s"].as_str().filter(|s| is_seat(s) && *s != g.me).map(str::to_string)
            } else {
                None
            }
        };
        match t {
            "inv" => {
                let me = o["me"].as_str().unwrap_or("");
                if !is_seat(me) {
                    return Verdict::Refused;
                }
                let born = crate::book::birth_ms(copy).unwrap_or(0);
                if let Some(g) = &g {
                    if g.owner.is_empty() || g.owner != pipe {
                        return Verdict::Refused; // a group held by another owner
                    }
                    if g.left && g.me == me {
                        return Verdict::Refused;
                    }
                    if born > 0 && born < g.said_at {
                        return Verdict::Held; // an older invitation after a newer one: answered, never applied
                    }
                }
                let title: String = strip_crown(o["ti"].as_str().unwrap_or("").trim()).chars().take(64).collect();
                let fresh = g.as_ref().is_none_or(|g| g.left);
                let renamed = g.as_ref().is_some_and(|g| !g.title.is_empty() && g.title != title);
                let had_face = g.as_ref().is_some_and(|g| !g.face_tag.is_empty());
                let face = o["fc"].as_str().filter(|fc| g.as_ref().is_none_or(|g| g.face_tag != face_tag(fc)))
                    .and_then(|fc| face_of(fc).map(|b| (fc.to_string(), b)));
                let mut all = self.held();
                let s = all.entry(gid.to_string()).or_insert_with(|| Group { id: gid.into(), ..Default::default() });
                s.owner = pipe.to_string();
                s.me = me.to_string();
                s.kind = o["k"].as_str().filter(|k| *k == "c").unwrap_or("g").to_string();
                s.title = title.clone();
                s.about = o["ds"].as_str().unwrap_or("").chars().take(255).collect();
                s.count = o["c"].as_u64().unwrap_or(2).clamp(2, 201) as u32;
                s.admins = o["ad"].as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect()).unwrap_or_default();
                s.signs = s.kind == "c" && o["sg"] == json!(1);
                s.reacts_off = s.kind == "c" && o["rx"] == json!(0);
                take_rights(&o, s);
                if !name.is_empty() {
                    s.names.insert("0".into(), name);
                }
                s.left = false;
                s.removed = false;
                s.said_at = s.said_at.max(born);
                self.keep_groups(&all);
                self.book.edit(&chat_of(gid), |c| {
                    c.name = title.clone();
                    c.hidden = false;
                });
                let new_face = face.is_some_and(|(fc, b)| self.keep_face(gid, &b, &fc));
                if fresh {
                    self.event(gid, "added", "0", &[me.to_string()], "");
                    self.news.lock().unwrap().push(crate::post::News { chat: chat_of(gid), text: title, anon: None });
                } else if renamed {
                    self.event(gid, "named", "0", &[], &title);
                }
                if new_face && had_face && !fresh {
                    self.event(gid, "face", "0", &[], "");
                }
                Verdict::Held
            }
            _ => {
                if t == "ty" && g.as_ref().is_none_or(|g| g.left) {
                    return Verdict::Instant; // a typing word lives an instant: never kept for later, never answered
                }
                let Some(g) = g else { return Verdict::Wait }; // the invitation has not come yet
                if g.left && t != "inv" {
                    return Verdict::Refused;
                }
                match t {
                    "say" => {
                        let Some(seat) = seat_of(&g) else { return Verdict::Refused };
                        let (Some(id), Some(tx)) = (o["id"].as_str(), o["tx"].as_str()) else { return Verdict::Refused };
                        if !marks::is_row(tx) || id.len() > 80 || tx.is_empty() {
                            return Verdict::Refused;
                        }
                        if g.kind == "c" && g.owner.is_empty() && !(g.admins.contains(&seat) && admin_can(&g, &seat, "po")) {
                            return Verdict::Refused; // a channel carries its owner's and its administrators' posts alone (iOS «Post Messages»)
                        }
                        if g.owner.is_empty() && !quiet && !self.book.chat(&chat_of(gid)).is_some_and(|c| c.msgs.iter().any(|m| m.mid == id)) {
                            if !allows(&g, &seat, tx) {
                                return Verdict::Refused; // a letter past the group's permissions (iOS G.5)
                            }
                            if !pace_slow(&g, &seat) {
                                return Verdict::Wait; // slow mode: held unanswered, it knocks again
                            }
                        }
                        if !name.is_empty() {
                            self.edit_group(gid, |g| { g.names.insert(seat.clone(), name.clone()); });
                        }
                        let chat = chat_of(gid);
                        if self.book.chat(&chat).is_some_and(|c| c.msgs.iter().any(|m| m.mid == id)) {
                            return Verdict::Held; // heard before
                        }
                        let at = birth_ms(id).unwrap_or_else(wire::now_ms);
                        let (qt, qm) = (o["qt"].as_str().unwrap_or("").to_string(), o["qm"].as_str().unwrap_or("").trim_start_matches("mid:").to_string());
                        let row = Msg { mid: id.to_string(), text: tx.to_string(), mine: false, at, qt, qm, from: format!("gm:{gid}/{seat}"), ..Default::default() };
                        let past = o["hs"] == json!(1); // the group's past handed to one just added: read already, as it was before them
                        self.book.edit(&chat, |c| {
                            c.msgs.push(row);
                            c.msgs.sort_by_key(|m| m.at);
                            if !past {
                                c.unread += 1;
                            }
                            c.hidden = false;
                        });
                        self.presence.group_stopped(&chat, &seat); // the letter came: its speaker types no more
                        let who = g.names.get(&seat).cloned().filter(|n| !n.is_empty()).unwrap_or_else(|| name.clone());
                        let shown = if who.is_empty() || g.kind == "c" { tx.to_string() } else { format!("{who}: {tx}") }; // a channel speaks as itself
                        self.news.lock().unwrap().push(crate::post::News { chat: chat.clone(), text: shown, anon: Some(tx.to_string()) });
                        if g.owner.is_empty() && !quiet {
                            // the owner carries it on to everyone else, the speaker's seat and name with it
                            let mut relay = json!({ "t": "say", "g": gid, "k": g.kind, "ti": g.title, "id": id, "s": seat, "tx": tx });
                            for k in ["n", "qt", "qm", "sl"] {
                                if !o[k].is_null() {
                                    relay[k] = o[k].clone();
                                }
                            }
                            self.spread(&g, "", Some(&seat), relay);
                        }
                        Verdict::Held
                    }
                    "sig" => {
                        let Some(seat) = seat_of(&g) else { return Verdict::Refused };
                        let (Some(id), Some(tx)) = (o["id"].as_str(), o["tx"].as_str()) else { return Verdict::Refused };
                        if g.kind == "c" && g.owner.is_empty() && (!tx.starts_with(marks::REACT) || g.reacts_off) && !g.admins.contains(&seat) {
                            return Verdict::Refused; // a subscriber answers a post with a reaction alone, where the channel takes them
                        }
                        if g.kind == "c" && g.owner.is_empty() && !g.react_list.is_empty() && !g.admins.contains(&seat) {
                            let o2: Value = tx.strip_prefix(marks::REACT).and_then(|j| serde_json::from_str(j).ok()).unwrap_or_default();
                            if o2["op"] == json!("add") && !o2["e"].as_str().is_some_and(|e| g.react_list.iter().any(|x| x == e)) {
                                return Verdict::Refused; // a reaction outside the channel's list (iOS «Some Reactions»)
                            }
                        }
                        if g.heard.iter().any(|h| h == id) {
                            return Verdict::Held;
                        }
                        self.edit_group(gid, |g| {
                            g.heard.push(id.to_string());
                            if g.heard.len() > 512 {
                                g.heard.remove(0);
                            }
                        });
                        if tx.starts_with(marks::PIN) && !pins(&g, &seat) {
                            return Verdict::Refused; // a pin by a seat without the right
                        }
                        if g.owner.is_empty() && !allows(&g, &seat, tx) {
                            return Verdict::Refused; // a reaction or an edit past the group's permissions
                        }
                        // an edit or a deletion is the speaker's own; the owner and the administrators it named take another's letter
                        // away (iOS answered: «Delete Messages»)
                        let target = [marks::EDIT, marks::DELETE].iter().find_map(|m| tx.strip_prefix(m)).and_then(|j| {
                            if tx.starts_with(marks::DELETE) { Some(j.trim_start_matches("mid:").to_string()) }
                            else { serde_json::from_str::<Value>(j).ok().and_then(|v| v["sid"].as_str().map(|s| s.trim_start_matches("mid:").to_string())) }
                        });
                        if let Some(target) = target {
                            let row = self.book.chat(&chat_of(gid)).and_then(|c| c.msgs.into_iter().find(|m| m.mid == target));
                            let boss = tx.starts_with(marks::DELETE) && admin_can(&g, &seat, "dm");
                            let author = |r: &Msg| if r.mine { g.me == seat } else { r.from.ends_with(&format!("/{seat}")) };
                            if row.as_ref().is_some_and(|r| !author(r) && !boss) {
                                return Verdict::Refused; // an answer to another's letter
                            }
                        }
                        self.place_answer(&chat_of(gid), &seat, tx);
                        if g.owner.is_empty() && !quiet {
                            let mut relay = json!({ "t": "sig", "g": gid, "id": id, "s": seat, "tx": tx });
                            if !name.is_empty() {
                                relay["n"] = json!(name);
                            }
                            self.spread(&g, "", Some(&seat), relay);
                        }
                        Verdict::Held
                    }
                    "out" => {
                        if g.owner != pipe {
                            return Verdict::Refused;
                        }
                        let born = crate::book::birth_ms(copy).unwrap_or(0);
                        if born > 0 && born < g.said_at {
                            return Verdict::Held; // a taking-out older than the invitation that stands: answered, never applied
                        }
                        self.edit_group(gid, |g| {
                            g.left = true;
                            g.removed = true;
                            g.said_at = g.said_at.max(born);
                        });
                        if o["dl"] == json!(1) {
                            self.book.edit(&chat_of(gid), |c| c.msgs.clear());
                        }
                        self.event(gid, "removed", "0", std::slice::from_ref(&g.me), "");
                        Verdict::Held
                    }
                    "bye" => {
                        let Some(seat) = seat_of(&g).filter(|_| g.owner.is_empty()) else { return Verdict::Refused };
                        let g = self.edit_group(gid, |g| {
                            g.members.retain(|m| m.seat != seat);
                            g.admins.retain(|a| *a != seat);
                            g.count = g.members.len() as u32 + 1;
                        });
                        if let Some(g) = g {
                            if !quiet {
                                self.tell_all(&g, None, None);
                                self.tell_event(&g, "left", &seat, std::slice::from_ref(&seat));
                            }
                            self.event(gid, "left", &seat, &[], "");
                        }
                        Verdict::Held
                    }
                    "ev" => {
                        if g.owner != pipe {
                            return Verdict::Refused;
                        }
                        let Some(ev) = o["tx"].as_str().filter(|t| t.len() <= 4096).and_then(|t| serde_json::from_str::<Value>(t).ok()) else { return Verdict::Refused };
                        let e = ev["e"].as_str().unwrap_or("");
                        if !["added", "removed", "left", "joined"].contains(&e) {
                            return Verdict::Refused;
                        }
                        let people: Vec<String> = ev["p"].as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect()).unwrap_or_default();
                        self.event(gid, e, ev["a"].as_str().unwrap_or("0"), &people, "");
                        Verdict::Held
                    }
                    "rd" => {
                        let ms: i64 = o["tx"].as_str().and_then(|s| s.parse().ok()).unwrap_or(0);
                        if g.owner.is_empty() {
                            let Some(seat) = seat_of(&g) else { return Verdict::Refused };
                            if quiet {
                                self.read_mine(gid, &seat, ms); // the copy reads my letters here; the carrying was the other device's
                            } else {
                                self.spread_read(&g, &seat, ms);
                            }
                        } else {
                            if g.owner != pipe {
                                return Verdict::Refused;
                            }
                            let reader = o["s"].as_str().unwrap_or("");
                            let to_me = o["ts"].as_array().is_none_or(|a| a.iter().any(|x| x.as_str() == Some(g.me.as_str())));
                            if is_seat(reader) && to_me {
                                self.read_mine(gid, reader, ms);
                            }
                        }
                        Verdict::Held
                    }
                    "lp" => {
                        // a letter's card (iOS carded): onto the letter of the same speaker whose words hold its link
                        let Some(seat) = seat_of(&g) else { return Verdict::Refused };
                        let (Some(id), Some(lp)) = (o["id"].as_str(), o["tx"].as_str().filter(|t| t.len() <= 16_384)) else { return Verdict::Refused };
                        let Some(card) = crate::linkcard::parse(lp) else { return Verdict::Refused };
                        let chat = chat_of(gid);
                        let Some(row) = self.book.chat(&chat).and_then(|c| c.msgs.into_iter().find(|m| m.mid == id)) else {
                            let fresh = birth_ms(id).is_some_and(|b| wire::now_ms() - b < 600_000);
                            return if fresh { Verdict::Wait } else { Verdict::Refused }; // the card came before its letter (iOS cardWait)
                        };
                        if row.mine || !row.from.ends_with(&format!("/{seat}")) || !crate::linkcard::urls(&row.text).iter().any(|u| Some(u.as_str()) == card["u"].as_str()) {
                            return Verdict::Refused; // a card past its letter's speaker or its words
                        }
                        if let Some(lp) = crate::linkcard::enrich(&row.lp, &card.to_string()) {
                            self.book.edit(&chat, |c| { if let Some(m) = c.msgs.iter_mut().find(|m| m.mid == id) { m.lp = lp.clone(); } });
                        }
                        if g.owner.is_empty() && !quiet {
                            self.spread(&g, "", Some(&seat), json!({ "t": "lp", "g": gid, "id": id, "s": seat, "tx": lp }));
                        }
                        Verdict::Held
                    }
                    "kk" => {
                        // an administrator's «take out», at the owner's (iOS kicked): the asker may ban, the person is a member and none
                        let Some(asker) = seat_of(&g).filter(|_| g.owner.is_empty()) else { return Verdict::Refused };
                        let target = o["s"].as_str().unwrap_or("");
                        if !admin_can(&g, &asker, "bu") || target == asker || g.admins.iter().any(|a| a == target) || !g.members.iter().any(|m| m.seat == target) {
                            return Verdict::Refused;
                        }
                        if !quiet {
                            self.group_remove_by(gid, target, &asker);
                        }
                        Verdict::Held
                    }
                    "ci" => {
                        // a member's renewal at the owner's (iOS infoAsked): an administrator with the right, or a member the group lets
                        let Some(asker) = seat_of(&g).filter(|_| g.owner.is_empty()) else { return Verdict::Refused };
                        if !(admin_can(&g, &asker, "ci") || (g.kind == "g" && !g.barred.iter().any(|b| b == "ci"))) {
                            return Verdict::Refused;
                        }
                        let title: String = strip_crown(o["ti"].as_str().unwrap_or("").trim()).chars().take(64).collect();
                        if quiet {
                            return Verdict::Held;
                        }
                        let face = o["fc"].as_str().and_then(|fc| face_of(fc).map(|b| (fc.to_string(), b)));
                        let renamed = !title.is_empty() && title != g.title;
                        let about = o["ds"].as_str().map(|d| d.trim().chars().take(255).collect::<String>());
                        let Some(g) = self.edit_group(gid, |g| {
                            if renamed {
                                g.title = title.clone();
                            }
                            if let Some(d) = &about {
                                g.about = d.clone();
                            }
                        }) else { return Verdict::Refused };
                        if renamed {
                            self.book.edit(&chat_of(gid), |c| c.name = title.clone());
                            self.event(gid, "named", &asker, &[], &title);
                        }
                        let fc = face.filter(|(fc, b)| self.keep_face(gid, b, fc)).map(|(fc, _)| fc);
                        if fc.is_some() {
                            self.event(gid, "face", &asker, &[], "");
                        }
                        self.tell_all(&g, fc.as_deref(), None);
                        Verdict::Held
                    }
                    "jn" => {
                        // one who opened the group's link (iOS joined): the mark must be the group's standing one; one taken out
                        // does not come back by it; the person is added by the owner's own road, and everyone reads they joined
                        if !g.owner.is_empty() || g.invite.is_empty() || o["tx"].as_str() != Some(g.invite.as_str()) {
                            return Verdict::Refused;
                        }
                        if g.members.iter().any(|m| m.pipe == pipe) {
                            return Verdict::Held;
                        }
                        if g.banned.iter().any(|b| b == pipe) || g.members.len() >= PEOPLE - 1 {
                            return Verdict::Refused;
                        }
                        if g.approval {
                            // the link asks the owner first (iOS G.8): the asker waits among the requests, once, until the owner
                            // adds or dismisses them
                            self.edit_group(gid, |g| {
                                g.requests.retain(|r| r.pipe != pipe);
                                g.requests.push(Request { pipe: pipe.to_string(), name: name.clone(), at: wire::now_ms() });
                                let over = g.requests.len().saturating_sub(PEOPLE);
                                g.requests.drain(..over);
                            });
                            return Verdict::Held;
                        }
                        self.admit(gid, pipe, &name, quiet)
                    }
                    "cm" => {
                        // a comment under a channel's post (iOS commented): the owner takes one under a post of its feed, from a
                        // subscriber it carries to, while comments are on, one in thirty seconds a seat, and carries it on to everyone
                        // else; a subscriber takes the owner's word alone; each comment once, by its name
                        let (Some(id), Some(post), Some(tx)) = (o["id"].as_str(), o["qm"].as_str(), o["tx"].as_str()) else { return Verdict::Refused };
                        if g.kind != "c" || tx.is_empty() || tx.chars().count() > COMMENT_LIMIT {
                            return Verdict::Refused;
                        }
                        let Some(seat) = seat_of(&g) else { return Verdict::Refused };
                        let chat = chat_of(gid);
                        if comments_of(self.vault, &chat).get(post).is_some_and(|l| l.iter().any(|c| c.id == id)) {
                            return Verdict::Held;
                        }
                        if g.owner.is_empty() {
                            if !g.talks || !self.book.chat(&chat).is_some_and(|c| c.msgs.iter().any(|m| m.mid == post)) {
                                return Verdict::Refused;
                            }
                            if !quiet {
                                let mut at = COMMENT_AT.lock().unwrap();
                                let at = at.get_or_insert_with(BTreeMap::new);
                                let k = format!("{gid}/{seat}");
                                if wire::now_ms() - at.get(&k).copied().unwrap_or(0) < COMMENT_GAP_MS {
                                    return Verdict::Refused;
                                }
                                at.insert(k, wire::now_ms());
                            }
                        }
                        let fresh = put_comment(self.vault, &chat, post, Comment { id: id.into(), seat: seat.clone(), name: name.clone(), text: tx.into(),
                                                                                  at: birth_ms(id).unwrap_or_else(wire::now_ms), mine: false });
                        if fresh && g.owner.is_empty() && !quiet {
                            let mut relay = json!({ "t": "cm", "g": gid, "id": id, "s": seat, "tx": tx, "qm": post });
                            if !name.is_empty() {
                                relay["n"] = json!(name);
                            }
                            self.spread(&g, "", Some(&seat), relay);
                        }
                        Verdict::Held
                    }
                    "vw" => {
                        // a subscriber's posts shown, at the owner's: the seat is the pipe's, and only posts of this channel's feed count
                        if !g.owner.is_empty() || g.kind != "c" {
                            return Verdict::Refused;
                        }
                        let (Some(seat), Some(tx)) = (seat_of(&g), o["tx"].as_str().filter(|t| t.len() <= 16_384)) else { return Verdict::Refused };
                        let posts: std::collections::HashSet<String> = self.book.chat(&chat_of(gid)).map(|c| c.msgs.into_iter()
                            .filter(|m| marks::is_row(&m.text)).map(|m| m.mid).collect()).unwrap_or_default();
                        let letters: Vec<String> = tx.split(',').take(VIEWS_BATCH).filter(|l| posts.contains(*l)).map(str::to_string).collect();
                        self.channel_saw(gid, &seat, &letters, !quiet);
                        Verdict::Held
                    }
                    "vc" => {
                        // the owner's numbers, from the owner's pipe alone
                        if g.owner != pipe || g.kind != "c" {
                            return Verdict::Refused;
                        }
                        let Some(numbers) = o["tx"].as_str().filter(|t| t.len() <= 16_384).and_then(|t| serde_json::from_str::<BTreeMap<String, u32>>(t).ok()) else { return Verdict::Refused };
                        self.channel_told(gid, &numbers);
                        Verdict::Held
                    }
                    "room" => {
                        // A ROOM'S WORD (iOS roomed): its seat proven by the pipe it came by; the room reads it once by its name, and
                        // the owner passes it on to everyone else -- a targeted word to the seats it names alone
                        let Some(seat) = seat_of(&g) else { return Verdict::Refused };
                        let (Some(id), Some(tx)) = (o["id"].as_str(), o["tx"].as_str()) else { return Verdict::Refused };
                        if id.is_empty() || id.len() > 80 || tx.len() > 4096 {
                            return Verdict::Refused;
                        }
                        if g.heard.iter().any(|h| h == id) {
                            return Verdict::Held;
                        }
                        self.edit_group(gid, |g| {
                            g.heard.push(id.to_string());
                            if g.heard.len() > 512 {
                                g.heard.remove(0);
                            }
                        });
                        if !name.is_empty() && g.names.get(&seat) != Some(&name) {
                            self.edit_group(gid, |g| { g.names.insert(seat.clone(), name.clone()); });
                        }
                        crate::rooms::heard(self, tx, gid, &seat, &name);
                        if g.owner.is_empty() && !quiet {
                            let mut on = json!({ "t": "room", "g": gid, "k": g.kind, "ti": g.title, "id": id, "s": seat, "tx": tx });
                            if !name.is_empty() {
                                on["n"] = json!(name);
                            }
                            match o["ts"].as_array().filter(|a| a.len() <= 32) {
                                Some(ts) => {
                                    let ts: Vec<String> = ts.iter().filter_map(|x| x.as_str().map(str::to_string)).collect();
                                    let ring = o["rg"] == json!(1) || o["rg"].is_null();
                                    on["ts"] = json!(ts);
                                    on["rg"] = json!(if ring { 1 } else { 0 });
                                    let to: Vec<&Member> = g.members.iter().filter(|m| ts.contains(&m.seat) && m.seat != seat).collect();
                                    for m in &to {
                                        self.carry(gid, "", &m.pipe, to.len() as u32, on.clone());
                                    }
                                }
                                None => {
                                    self.spread(&g, "", Some(&seat), on);
                                }
                            }
                        }
                        Verdict::Held
                    }
                    "ty" => {
                        // a member typing (iOS typed): its seat proven by the pipe it came by, as every word's is; the owner throws
                        // it on to the other members, once in two seconds a member; a group's alone
                        if g.kind != "g" || quiet {
                            return Verdict::Instant;
                        }
                        let Some(seat) = seat_of(&g) else { return Verdict::Instant };
                        if g.owner.is_empty() && self.presence.throw_due(&format!("{gid}/{seat}")) {
                            let mut on = o.clone();
                            on["s"] = json!(seat);
                            let to: Vec<String> = g.members.iter().filter(|m| m.seat != seat).map(|m| m.pipe.clone()).collect();
                            self.throw_typing(&to, &word(on));
                        }
                        if !name.is_empty() && g.names.get(&seat) != Some(&name) {
                            self.edit_group(gid, |g| { g.names.insert(seat.clone(), name.clone()); });
                        }
                        self.presence.group_typed(&chat_of(gid), &seat);
                        Verdict::Instant
                    }
                    _ => Verdict::Refused, // a kind this build does not know: answered, never applied
                }
            }
        }
    }

    /// THE PERSON'S OWN GROUP WORD FROM ANOTHER OF THEIR DEVICES (iOS MTGroup.handleOwn + replay): what that device said is what
    /// this person said, so it is done here as the hand did it there -- an invitation stands the group as mine with that member
    /// at the seat the word gave, a letter its row (mine when the seat is mine, a member's when I carried it), a taking out and
    /// a leaving their state -- and nothing is said to anyone again.
    pub fn group_own(&self, pipe: &str, text: &str) {
        let Some(o) = text.strip_prefix(MARK).and_then(|j| serde_json::from_str::<Value>(j).ok()) else { return };
        let (Some(t), Some(gid)) = (o["t"].as_str(), o["g"].as_str()) else { return };
        if gid.len() != 32 || !gid.chars().all(|c| c.is_ascii_hexdigit()) {
            return;
        }
        match t {
            "inv" => {
                let title: String = strip_crown(o["ti"].as_str().unwrap_or("").trim()).chars().take(64).collect();
                let seat = o["me"].as_str().unwrap_or("");
                if title.is_empty() || !is_seat(seat) || seat == "0" {
                    return;
                }
                let g = self.group(gid);
                if g.as_ref().is_some_and(|g| !g.owner.is_empty()) {
                    return; // an own invitation of a group this machine holds as a member
                }
                let fresh = g.is_none();
                let renamed = g.as_ref().is_some_and(|g| g.title != title);
                let face = o["fc"].as_str().filter(|fc| g.as_ref().is_none_or(|g| g.face_tag != face_tag(fc)))
                    .and_then(|fc| face_of(fc).map(|b| (fc.to_string(), b)));
                let mut all = self.held();
                let s = all.entry(gid.to_string()).or_insert_with(|| Group { id: gid.into(), me: "0".into(), ..Default::default() });
                s.kind = o["k"].as_str().filter(|k| *k == "c").unwrap_or("g").to_string();
                s.title = title.clone();
                s.about = o["ds"].as_str().unwrap_or("").chars().take(255).collect();
                s.members.retain(|m| m.seat != seat && m.pipe != pipe);
                s.members.push(Member { seat: seat.to_string(), pipe: pipe.to_string() });
                s.count = (s.members.len() as u32 + 1).max(o["c"].as_u64().unwrap_or(2).min(201) as u32);
                s.admins = o["ad"].as_array().map(|a| a.iter().filter_map(|x| x.as_str().filter(|x| is_seat(x)).map(str::to_string)).collect()).unwrap_or_default();
                s.signs = s.kind == "c" && o["sg"] == json!(1);
                s.reacts_off = s.kind == "c" && o["rx"] == json!(0);
                take_rights(&o, s);
                s.left = false;
                self.keep_groups(&all);
                self.book.edit(&chat_of(gid), |c| {
                    c.name = title.clone();
                    c.hidden = false;
                });
                if fresh {
                    self.event(gid, "made", "0", &[], &title);
                } else if renamed {
                    self.event(gid, "named", "0", &[], &title);
                }
                if let Some((fc, b)) = face {
                    self.keep_face(gid, &b, &fc);
                }
            }
            "say" => {
                let Some(g) = self.group(gid).filter(|g| !g.left) else { return };
                let (Some(id), Some(tx), Some(seat)) = (o["id"].as_str(), o["tx"].as_str(), o["s"].as_str()) else { return };
                if id.is_empty() || id.len() > 80 || tx.is_empty() || !marks::is_row(tx) || !is_seat(seat) {
                    return;
                }
                let chat = chat_of(gid);
                if self.book.chat(&chat).is_some_and(|c| c.msgs.iter().any(|m| m.mid == id) || c.graves.iter().any(|x| x == id)) {
                    return;
                }
                let mine = seat == g.me;
                let at = birth_ms(id).unwrap_or_else(wire::now_ms);
                let (qt, qm) = (o["qt"].as_str().unwrap_or("").to_string(), o["qm"].as_str().unwrap_or("").trim_start_matches("mid:").to_string());
                let row = Msg { mid: id.to_string(), text: tx.to_string(), mine, at, state: if mine { 1 } else { 0 }, qt, qm,
                                from: if mine { String::new() } else { format!("gm:{gid}/{seat}") }, ..Default::default() };
                if let Some(n) = o["n"].as_str().map(|n| strip_crown(n.trim()).chars().take(64).collect::<String>()).filter(|n| !n.is_empty() && !mine) {
                    self.edit_group(gid, |g| { g.names.insert(seat.to_string(), n); });
                }
                self.book.edit(&chat, |c| {
                    c.msgs.push(row);
                    c.msgs.sort_by_key(|m| m.at);
                    if !mine {
                        c.unread += 1;
                    }
                    c.hidden = false;
                });
            }
            "out" => {
                let Some(g) = self.group(gid).filter(|g| g.owner.is_empty()) else { return };
                let Some(m) = g.members.iter().find(|m| m.pipe == pipe).cloned() else { return };
                self.edit_group(gid, |g| {
                    g.members.retain(|x| x.seat != m.seat);
                    g.admins.retain(|a| *a != m.seat);
                    g.count = g.members.len() as u32 + 1;
                });
                self.event(gid, "removed", "0", &[m.seat], "");
            }
            "bye" => {
                if self.group(gid).is_some_and(|g| !g.owner.is_empty() && !g.left) {
                    self.edit_group(gid, |g| g.left = true);
                    self.event(gid, "left", &self.group(gid).map(|g| g.me).unwrap_or_default(), &[], "");
                }
            }
            _ => {} // the other device's word to the group: applied to nobody here
        }
    }

    /// An answer in a group's feed (a reaction, an edit, a deletion, a pin), applied as the pair's are.
    fn place_answer(&self, chat: &str, seat: &str, tx: &str) {
        let _ = seat;
        self.place_word(chat, tx);
    }
}

/// The words an event row says (iOS eventWords), in the window's language; «the owner» and seats by their names.
pub fn event_words(e: &Value, names: &BTreeMap<String, String>, me: &str, ru: bool) -> String {
    let who = |s: &str| -> String {
        if s == me {
            return if ru { "Вы".into() } else { "You".into() };
        }
        names.get(s).cloned().filter(|n| !n.is_empty()).unwrap_or_else(|| if ru { "Участник".into() } else { "Member".into() })
    };
    let people: Vec<String> = e["p"].as_array().map(|a| a.iter().filter_map(|x| x.as_str()).map(|s| if s == me { if ru { "вас".to_string() } else { "you".to_string() } } else { who(s) }).collect()).unwrap_or_default();
    let a = e["a"].as_str().unwrap_or("0");
    let mine = a == me;
    let t = e["t"].as_str().unwrap_or("");
    let p = people.join(", ");
    match (e["e"].as_str().unwrap_or(""), ru) {
        ("made", true) => if mine { format!("Вы создали группу «{t}»") } else { format!("{} создал(а) группу «{t}»", who(a)) },
        ("made", false) => if mine { format!("You created the group «{t}»") } else { format!("{} created the group «{t}»", who(a)) },
        ("added", true) => if mine { format!("Вы добавили {p}") } else { format!("{} добавил(а) {p}", who(a)) },
        ("added", false) => if mine { format!("You added {p}") } else { format!("{} added {p}", who(a)) },
        ("removed", true) => if mine { format!("Вы удалили {p}") } else { format!("{} удалил(а) {p}", who(a)) },
        ("removed", false) => if mine { format!("You removed {p}") } else { format!("{} removed {p}", who(a)) },
        ("left", true) => if mine { "Вы покинули группу".into() } else { format!("{} покинул(а) группу", who(a)) },
        ("left", false) => if mine { "You left the group".into() } else { format!("{} left the group", who(a)) },
        ("joined", true) => format!("{} вступил(а) в группу по ссылке-приглашению", who(a)),
        ("joined", false) => format!("{} joined the group by the invite link", who(a)),
        ("named", true) => if mine { format!("Вы изменили название группы на «{t}»") } else { format!("{} изменил(а) название группы на «{t}»", who(a)) },
        ("named", false) => if mine { format!("You renamed the group to «{t}»") } else { format!("{} renamed the group to «{t}»", who(a)) },
        ("face", true) => if mine { "Вы изменили фото группы".into() } else { format!("{} изменил(а) фото группы", who(a)) },
        ("face", false) => if mine { "You changed the group photo".into() } else { format!("{} changed the group photo", who(a)) },
        ("call", _) => {
            let (live, video) = (e["k"].as_str() == Some("live"), e["v"] == json!(1));
            match (ru, live, video, mine) {
                (true, true, _, true) => "Вы начали трансляцию".into(),
                (true, true, _, false) => format!("{} начал(а) трансляцию", who(a)),
                (true, false, true, true) => "Вы начали видеочат".into(),
                (true, false, true, false) => format!("{} начал(а) видеочат", who(a)),
                (true, false, false, true) => "Вы начали голосовой чат".into(),
                (true, false, false, false) => format!("{} начал(а) голосовой чат", who(a)),
                (false, true, _, true) => "You started a live stream".into(),
                (false, true, _, false) => format!("{} started a live stream", who(a)),
                (false, false, true, true) => "You started a video chat".into(),
                (false, false, true, false) => format!("{} started a video chat", who(a)),
                (false, false, false, true) => "You started a voice chat".into(),
                (false, false, false, false) => format!("{} started a voice chat", who(a)),
            }
        }
        ("ended", _) => {
            let s = e["d"].as_i64().unwrap_or(0).max(0);
            let span = if s >= 3600 { format!("{}:{:02}:{:02}", s / 3600, s % 3600 / 60, s % 60) } else { format!("{}:{:02}", s / 60, s % 60) };
            match (ru, e["k"].as_str() == Some("live"), e["v"] == json!(1)) {
                (true, true, _) => format!("Трансляция завершена ({span})"),
                (true, false, true) => format!("Видеочат завершён ({span})"),
                (true, false, false) => format!("Голосовой чат завершён ({span})"),
                (false, true, _) => format!("Live stream ended ({span})"),
                (false, false, true) => format!("Video chat ended ({span})"),
                (false, false, false) => format!("Voice chat ended ({span})"),
            }
        }
        _ => String::new(),
    }
}

/// The groups this machine holds, read without a desk (the window's views).
pub fn held_of(vault: &crate::vault::Vault) -> BTreeMap<String, Group> {
    vault.get(HELD).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::book::Book;
    use crate::card::Card;
    use crate::post::Desk;
    use crate::vault::Vault;
    use crate::{media, meeting, seed};

    struct Person {
        vault: Vault,
        book: Book,
        store: media::Store,
        presence: crate::presence::Presence,
        words: String,
        twin: String,
        name: String,
    }

    fn person(root: &std::path::Path, n: &str) -> Person {
        let vault = Vault::at(&root.join(n)).unwrap();
        let words = seed::generate().unwrap();
        Person { book: Book::new(vault.clone()), store: media::Store::at(&root.join(format!("{n}-media"))).unwrap(), presence: Default::default(),
                 twin: seed::twin_of(&words).unwrap(), words, vault, name: n.into() }
    }

    fn desk(p: &Person) -> Desk<'_> {
        Desk { vault: &p.vault, book: &p.book, twin: p.twin.clone(), author_key: seed::author_key_of(&p.words), my_name: p.name.clone(),
               news: Default::default(), media: &p.store, faces: &p.store, self_face: vec![], about: Default::default(), read_receipts: true,
               presence: &p.presence, archive: None }
    }

    #[test]
    fn one_added_reads_the_newest_past_by_its_speakers() {
        let mut g = Group { id: "0123456789abcdef0123456789abcdef".into(), kind: "g".into(), me: "0".into(), title: "Тройка".into(), ..Default::default() };
        g.names.insert("b0b0b0b0".into(), "Bob".into());
        let row = |i: usize, mine: bool, from: &str, text: &str| crate::book::Msg { mid: format!("m{i}"), text: text.into(), mine, at: i as i64,
                                                                                  from: from.into(), ..Default::default() };
        let gm = format!("gm:{}/b0b0b0b0", g.id);
        let mut msgs: Vec<crate::book::Msg> = (0..60).map(|i| row(i, i % 2 == 0, if i % 2 == 0 { "" } else { &gm }, &format!("слово {i}"))).collect();
        msgs.push(row(60, false, &gm, &format!("{}{{\"k\":\"img\"}}", marks::MEDIA)));
        msgs.push(row(61, false, &format!("gm:{}/c0c0c0c0", g.id), "от новенькой"));
        assert!(past_words(&g, &msgs, &["c0c0c0c0".into()], "Alice").is_empty(), "hidden: nothing");
        g.history = true;
        let w = past_words(&g, &msgs, &["c0c0c0c0".into()], "Alice");
        assert_eq!(w.len(), 49, "the newest fifty letters of words, the file and the newcomer's own aside");
        assert_eq!(w.last().unwrap()["tx"], json!("слово 59"));
        assert!(w.iter().all(|o| o["hs"] == json!(1)), "silent, the past");
        let bob = w.iter().find(|o| o["s"] == json!("b0b0b0b0")).unwrap();
        assert_eq!(bob["n"], json!("Bob"));
        assert!(w.iter().any(|o| o["s"] == json!("0") && o["n"] == json!("Alice")), "the owner's own under its name");
        g.kind = "c".into();
        let posts = past_words(&g, &msgs, &[], "Alice");
        assert_eq!(posts.len(), 10, "a channel: its owner's newest ten posts");
        assert!(posts.iter().all(|o| o["s"] == json!("0") && o["hs"].is_null()));
    }

    #[test]
    fn an_older_invitation_never_overwrites_a_newer() {
        let root = std::env::temp_dir().join(format!("montana-group-order-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let b = person(&root, "Bob");
        let db = desk(&b);
        let owner = b.book.establish(&[9u8; 32]).unwrap();
        b.book.open(&owner, "Alice", false);
        let gid = "0123456789abcdef0123456789abcdef";
        let inv = |ad: Value| word(json!({ "t": "inv", "g": gid, "k": "g", "ti": "Тройка", "c": 3, "me": "b0b0b0b0", "ad": ad }));
        let (old, new) = (mint_mid(), { std::thread::sleep(std::time::Duration::from_millis(5)); mint_mid() });
        assert_eq!(db.group_handle(&owner, &new, &inv(json!(["b0b0b0b0"])), false), Verdict::Held);
        assert_eq!(db.group_handle(&owner, &old, &inv(json!([])), false), Verdict::Held, "the older copy is answered");
        assert_eq!(db.group(gid).unwrap().admins, vec!["b0b0b0b0".to_string()], "and never applied over the newer");
        let later = mint_mid();
        assert_eq!(db.group_handle(&owner, &later, &inv(json!([])), false), Verdict::Held);
        assert!(db.group(gid).unwrap().admins.is_empty(), "a newer one is");
        let _ = std::fs::remove_dir_all(&root);
    }

    fn wait(d: &Desk, ok: &dyn Fn() -> bool) -> bool {
        for _ in 0..20 {
            d.fetch_once();
            d.group_retry();
            if ok() {
                return true;
            }
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
        false
    }

    /// A GROUP'S ROOM OF THREE, LIVE (iOS MTGroupRoom): Alice opens a voice chat in her group and invites Bob and Carol by the
    /// group's road; Bob sees the room under her name and comes in, and his offer -- sealed to Alice's room key -- reaches her alone
    /// on their pair's lane, her answer him; Carol comes in and offers to both; Carol goes out, Alice ends it for everyone, and the
    /// feed holds the room's rows. Run with --ignored and MONTANA_LIVE=1.
    #[test]
    #[ignore]
    fn a_room_of_three_opens_its_pairs_through_the_group() {
        let root = std::env::temp_dir().join(format!("montana-room-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (a, b, c) = (person(&root, "Alice"), person(&root, "Bob"), person(&root, "Carol"));
        let (da, db, dc) = (desk(&a), desk(&b), desk(&c));
        let link = (Card { vault: &a.vault }).offer_permanent("Alice").unwrap();
        let meet = |p: &Person| -> String {
            for _ in 0..10 {
                if let meeting::Outcome::Opened(r) = meeting::meet(&p.vault, &p.book, &link) {
                    return r;
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
            }
            panic!("no meeting")
        };
        let (rb, rc) = (meet(&b), meet(&c));
        db.send(&rb, "Привет от Боба");
        dc.send(&rc, "Привет от Кэрол");
        assert!(wait(&da, &|| a.book.all().iter().filter(|x| !x.msgs.is_empty()).count() == 2), "Alice did not hear both");
        let pipes: Vec<String> = a.book.all().into_iter().filter(|x| !x.msgs.is_empty()).map(|x| x.reference).collect();
        for p in &pipes {
            da.send(p, "Привет!");
        }
        assert!(wait(&db, &|| meeting::first(&b.vault, &rb).is_none()));
        assert!(wait(&dc, &|| meeting::first(&c.vault, &rc).is_none()));
        let chat = da.group_create("Созвон", &pipes).unwrap();
        let id = chat.strip_prefix("grp:").unwrap().to_string();
        assert!(wait(&db, &|| db.group(&id).is_some()) && wait(&dc, &|| dc.group(&id).is_some()), "the invitations never came");
        let (bob, carol) = (db.group(&id).unwrap().me, dc.group(&id).unwrap().me);

        // Alice opens the room and invites both: the invitation shows under her name, the room stands in each one's bar
        crate::rooms::open(&da, &chat, "call", false, &[bob.clone(), carol.clone()]).unwrap();
        let room = |d: &Desk| crate::rooms::state_now(d)["rooms"][&chat].clone();
        assert!(wait(&db, &|| room(&db)["asker"] == json!("Alice")), "Bob never saw Alice's invitation: {}", room(&db));
        assert!(db.news.lock().unwrap().iter().any(|n| n.text.contains("приглашает вас в голосовой чат")), "no banner for Bob");
        assert!(wait(&dc, &|| room(&dc)["count"] == json!(1)));

        // Bob comes in: Alice sees him, and holds his room key
        crate::rooms::join(&db, &chat, false).unwrap();
        let people = |d: &Desk| -> Vec<String> { crate::rooms::state_now(d)["live"]["people"].as_array().into_iter().flatten()
            .filter_map(|x| x["seat"].as_str().map(str::to_string)).collect() };
        let keyed = |d: &Desk, seat: &str| crate::rooms::state_now(d)["live"]["people"].as_array().into_iter().flatten()
            .any(|x| x["seat"] == json!(seat) && x["key"] == json!(true));
        assert!(wait(&da, &|| people(&da).contains(&bob) && keyed(&da, &bob)), "Alice never saw Bob come in");
        assert!(keyed(&db, "0"), "Bob holds Alice's room key from her words");

        // the later offers: Bob's offer reaches Alice alone, sealed to her key; her answer reaches him
        let caught = |twin: &str, from: &str, kind: &str| crate::rooms::CAUGHT.lock().unwrap().iter()
            .find(|(t, v)| t == twin && v["from"] == json!(from) && v["c"] == json!(kind)).map(|(_, v)| v.clone());
        let heard = |twin: &str, from: &str, kind: &str| -> Option<Value> {
            for _ in 0..30 {
                if let Some(v) = caught(twin, from, kind) {
                    return Some(v);
                }
                std::thread::sleep(std::time::Duration::from_secs(1));
            }
            None
        };
        assert!(crate::rooms::send(&db.twin, "0", "offer", 0, Some("v=0 offer of Bob".into()), None), "Bob's offer did not go");
        assert_eq!(heard(&a.twin, &bob, "offer").expect("Alice never heard Bob's offer")["sdp"], json!("v=0 offer of Bob"));
        assert!(crate::rooms::send(&da.twin, &bob, "answer", 0, Some("v=0 answer of Alice".into()), None));
        assert_eq!(heard(&b.twin, "0", "answer").expect("Bob never heard Alice's answer")["sdp"], json!("v=0 answer of Alice"));
        let ice = vec![crate::rooms::Ice { s: "candidate:1 1 udp 1 10.0.0.1 9 typ host".into(), i: 0, m: Some("0".into()) }];
        assert!(crate::rooms::send(&db.twin, "0", "ice", 0, None, Some(ice.clone())));
        assert_eq!(heard(&a.twin, &bob, "ice").expect("no candidates")["ice"][0]["s"], json!(ice[0].s));

        // Carol comes in: both see her; she holds both keys and offers to both
        crate::rooms::join(&dc, &chat, false).unwrap();
        assert!(wait(&da, &|| people(&da).contains(&carol)), "Alice never saw Carol");
        assert!(wait(&db, &|| { da.fetch_once(); people(&db).contains(&carol) }), "Bob never saw Carol");
        assert!(keyed(&dc, "0") && wait(&dc, &|| keyed(&dc, &bob)), "Carol lacks a key");
        assert!(crate::rooms::send(&dc.twin, &bob, "offer", 0, Some("v=0 offer of Carol".into()), None));
        assert_eq!(heard(&b.twin, &carol, "offer").expect("Bob never heard Carol")["sdp"], json!("v=0 offer of Carol"));
        assert!(caught(&a.twin, &carol, "offer").is_none(), "a pair's word reaches its pair alone");

        // Carol goes out; Alice ends the room for everyone: Bob is out of it, the feed holds its rows
        crate::rooms::leave(&dc);
        assert!(wait(&db, &|| { da.fetch_once(); !people(&db).contains(&carol) }), "Bob never saw Carol go");
        crate::rooms::end_for_everyone(&da);
        assert!(wait(&db, &|| crate::rooms::state_now(&db)["live"].is_null()), "Bob is still in an ended room");
        let rows = |p: &Person| -> Vec<String> { p.book.chat(&chat).unwrap().msgs.iter().filter_map(|m| m.text.strip_prefix(EVENT))
            .filter_map(|j| serde_json::from_str::<Value>(j).ok()).filter_map(|e| e["e"].as_str().map(str::to_string)).collect() };
        assert!(rows(&a).contains(&"call".to_string()) && rows(&a).contains(&"ended".to_string()), "Alice's feed: {:?}", rows(&a));
        assert!(wait(&db, &|| rows(&b).contains(&"ended".to_string())), "Bob's feed: {:?}", rows(&b));
        let ev = b.book.chat(&chat).unwrap().msgs.iter().filter_map(|m| m.text.strip_prefix(EVENT)).filter_map(|j| serde_json::from_str::<Value>(j).ok())
            .find(|e| e["e"] == json!("call")).unwrap();
        assert_eq!(event_words(&ev, &db.group(&id).unwrap().names, &bob, true), "Alice начал(а) голосовой чат");
        let _ = std::fs::remove_dir_all(&root);
    }

    /// A GROUP OF THREE, LIVE: Bob and Carol meet Alice's card; Alice makes a group of them; Bob writes into it, Alice
    /// carries it to Carol who sees Bob speaking; every copy answered, Bob's letter turns «delivered»; Carol reads it, and
    /// Bob's letter turns «read». Run with --ignored and MONTANA_LIVE=1.
    #[test]
    #[ignore]
    fn a_group_of_three_carries_a_letter_through_its_owner() {
        let root = std::env::temp_dir().join(format!("montana-group-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (a, b, c) = (person(&root, "Alice"), person(&root, "Bob"), person(&root, "Carol"));
        let (da, db, dc) = (desk(&a), desk(&b), desk(&c));
        let link = (Card { vault: &a.vault }).offer_permanent("Alice").unwrap();
        let meet = |p: &Person| -> String {
            for _ in 0..10 {
                if let meeting::Outcome::Opened(r) = meeting::meet(&p.vault, &p.book, &link) {
                    return r;
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
            }
            panic!("no meeting")
        };
        let (rb, rc) = (meet(&b), meet(&c));
        db.send(&rb, "Привет от Боба");
        dc.send(&rc, "Привет от Кэрол");
        assert!(wait(&da, &|| a.book.all().iter().filter(|x| !x.msgs.is_empty()).count() == 2), "Alice did not hear both");
        let pipes: Vec<String> = a.book.all().into_iter().filter(|x| !x.msgs.is_empty()).map(|x| x.reference).collect();
        // Alice answers each, so the introductions end and the pipes stand at both ends
        for p in &pipes {
            da.send(p, "Привет!");
        }
        assert!(wait(&db, &|| meeting::first(&b.vault, &rb).is_none()));
        assert!(wait(&dc, &|| meeting::first(&c.vault, &rc).is_none()));

        let chat = da.group_create("Тройка", &pipes).unwrap();
        let id = chat.strip_prefix("grp:").unwrap().to_string();
        assert!(wait(&db, &|| db.group(&id).is_some()), "Bob never got the invitation");
        assert!(wait(&dc, &|| dc.group(&id).is_some()), "Carol never got the invitation");
        assert_eq!(db.group(&id).unwrap().title, "Тройка");

        // Bob types: Alice sees him typing, and Carol too, thrown on by Alice; his letter ends it (iOS MTGroupTyping)
        let bob = db.group(&id).unwrap().me;
        db.group_typing(&id);
        assert!(wait(&da, &|| a.presence.group_typing(&chat) == vec![bob.clone()]), "Alice never saw Bob typing");
        assert!(wait(&dc, &|| c.presence.group_typing(&chat) == vec![bob.clone()]), "Carol never saw Bob typing through Alice");

        let mid = db.draft(&chat, "Всем привет из группы", "", "");
        assert!(db.post(&chat, &mid), "Bob's word did not go");
        assert!(wait(&da, &|| a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == mid)), "the owner never heard Bob");
        assert!(wait(&dc, &|| c.book.chat(&chat).is_some_and(|x| x.msgs.iter().any(|m| m.mid == mid))), "Carol never heard Bob through Alice");
        assert!(c.presence.group_typing(&chat).is_empty(), "Bob's letter ended his typing");
        let row = c.book.chat(&chat).unwrap().msgs.into_iter().find(|m| m.mid == mid).unwrap();
        assert!(row.from.ends_with(&format!("/{}", db.group(&id).unwrap().me)), "Carol sees whose letter it is");
        assert_eq!(dc.group(&id).unwrap().names.get(&db.group(&id).unwrap().me).map(String::as_str), Some("Bob"));
        assert!(wait(&db, &|| b.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == mid && m.state >= 2)), "the copy's receipt never came");

        dc.mark_read(&chat);
        assert!(wait(&db, &|| { da.fetch_once(); b.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == mid && m.state == 3) }), "Carol's reading never reached Bob");

        // the owner gives the group a photo: it rides the invitation, and both members show it
        let jpeg: Vec<u8> = [0xFF, 0xD8].into_iter().chain((0..6_000u32).map(|i| (i % 251) as u8)).collect();
        assert!(da.group_face(&id, &jpeg), "the owner could not give the group a photo");
        assert!(a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.text.starts_with(EVENT) && m.text.contains("\"e\":\"face\"")), "«You changed the group photo»");
        assert!(wait(&db, &|| b.store.get(&chat).as_deref() == Some(jpeg.as_slice())), "Bob never saw the group's photo");
        assert!(wait(&dc, &|| c.store.get(&chat).as_deref() == Some(jpeg.as_slice())), "Carol never saw the group's photo");
        assert!(b.book.chat(&chat).unwrap().face_at > 0 && !db.group(&id).unwrap().face_tag.is_empty());
        let _ = std::fs::remove_dir_all(&root);
    }

    /// A CHANNEL, LIVE: Bob and Carol meet Alice's card; Alice makes a channel of them; a subscriber's post goes nowhere; Alice's
    /// post reaches both, with no event rows; Bob's screen shows it and the eye under it counts two on Alice's machine and then on
    /// Bob's; Bob answers it with a reaction; Alice signs the posts and takes the reactions away, and Bob's next answer goes
    /// nowhere. Run with --ignored and MONTANA_LIVE=1.
    #[test]
    #[ignore]
    fn a_channel_carries_its_owners_posts_and_counts_their_views() {
        let root = std::env::temp_dir().join(format!("montana-channel-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (a, b, c) = (person(&root, "Alice"), person(&root, "Bob"), person(&root, "Carol"));
        let (da, db, dc) = (desk(&a), desk(&b), desk(&c));
        let link = (Card { vault: &a.vault }).offer_permanent("Alice").unwrap();
        let meet = |p: &Person| -> String {
            for _ in 0..10 {
                if let meeting::Outcome::Opened(r) = meeting::meet(&p.vault, &p.book, &link) {
                    return r;
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
            }
            panic!("no meeting")
        };
        let (rb, rc) = (meet(&b), meet(&c));
        db.send(&rb, "Привет от Боба");
        dc.send(&rc, "Привет от Кэрол");
        assert!(wait(&da, &|| a.book.all().iter().filter(|x| !x.msgs.is_empty()).count() == 2), "Alice did not hear both");
        let pipes: Vec<String> = a.book.all().into_iter().filter(|x| !x.msgs.is_empty()).map(|x| x.reference).collect();
        for p in &pipes {
            da.send(p, "Привет!");
        }
        assert!(wait(&db, &|| meeting::first(&b.vault, &rb).is_none()));
        assert!(wait(&dc, &|| meeting::first(&c.vault, &rc).is_none()));

        let chat = da.group_make("c", "Новости", "Канал для проверки", &pipes).unwrap();
        let id = chat.strip_prefix("grp:").unwrap().to_string();
        assert!(wait(&db, &|| db.group(&id).is_some_and(|g| g.kind == "c")), "Bob never got the channel");
        assert!(wait(&dc, &|| dc.group(&id).is_some()), "Carol never got the channel");
        assert_eq!(db.group(&id).unwrap().about, "Канал для проверки");
        let theirs = db.draft(&chat, "Подписчик пишет", "", "");
        assert!(!db.post(&chat, &theirs), "a subscriber's post goes nowhere");

        let post = da.send(&chat, "Первый пост канала");
        assert!(wait(&db, &|| b.book.chat(&chat).is_some_and(|x| x.msgs.iter().any(|m| m.mid == post))), "Bob never got the post");
        assert!(wait(&dc, &|| c.book.chat(&chat).is_some_and(|x| x.msgs.iter().any(|m| m.mid == post))), "Carol never got the post");
        assert!(!a.book.chat(&chat).unwrap().msgs.iter().chain(b.book.chat(&chat).unwrap().msgs.iter()).any(|m| m.text.starts_with(EVENT)),
                "a channel's feed holds its posts alone");

        // the eye: Bob's screen shows the post; Alice counts him and tells the number
        db.mark_read(&chat);
        assert!(wait(&da, &|| views_of(&a.vault, &chat, true).get(&post) == Some(&2)), "Alice never counted Bob's view");
        da.group_retry();
        assert!(wait(&db, &|| views_of(&b.vault, &chat, false).get(&post) == Some(&2)), "Bob never heard the number");

        // Bob answers the post; then Alice signs the posts and takes the reactions away
        db.react(&chat, &post, "🔥");
        assert!(wait(&da, &|| a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == post && m.peer_react == "🔥")), "Bob's reaction never came");
        da.channel_set(&id, true, false, false);
        assert!(wait(&db, &|| db.group(&id).is_some_and(|g| g.signs && g.reacts_off)), "Bob never heard the channel's ways");
        assert!(!db.group_deliver(&id, &crate::book::mint_mid(), &format!("{}{{}}", marks::REACT), "", ""), "no answer where the channel takes none");

        // comments: Alice lets subscribers talk; Bob comments the post, Alice carries it to Carol; a second one within 30 s waits
        da.channel_set(&id, true, true, true);
        assert!(wait(&db, &|| db.group(&id).is_some_and(|g| g.talks)), "Bob never heard the channel takes comments");
        assert!(db.channel_comment(&id, &post, "Хороший пост"), "Bob's comment did not go");
        assert!(!db.channel_comment(&id, &post, "Ещё один сразу"), "one comment in thirty seconds");
        assert!(wait(&da, &|| comments_of(&a.vault, &chat).get(&post).is_some_and(|l| l.iter().any(|c| c.text == "Хороший пост" && c.name == "Bob"))),
                "Alice never got Bob's comment");
        assert!(wait(&dc, &|| comments_of(&c.vault, &chat).get(&post).is_some_and(|l| l.iter().any(|c| c.text == "Хороший пост"))),
                "Carol never read Bob's comment");

        // Alice names Bob an administrator who posts but deletes no one's posts, titled «Редактор»: his post reaches Carol
        let bob = db.group(&id).unwrap().me;
        da.group_set_admin(&id, &bob, true, &["dm".to_string()], "Редактор");
        assert!(wait(&db, &|| db.group(&id).is_some_and(|g| g.admins.contains(&bob) && g.ranks.get(&bob).map(String::as_str) == Some("Редактор"))),
                "Bob never heard he is an administrator");
        let g = db.group(&id).unwrap();
        assert!(admin_can(&g, &bob, "po") && !admin_can(&g, &bob, "dm"), "the rights Alice left him");
        let his = db.draft(&chat, "Пост администратора", "", "");
        assert!(db.post(&chat, &his), "an administrator's post goes through the owner");
        assert!(wait(&da, &|| a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == his)), "Alice never got Bob's post");
        assert!(wait(&dc, &|| c.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == his)), "Carol never got Bob's post");

        // Alice takes 👍 alone: Carol's 😂 under the post is not taken, her 👍 is
        da.channel_reactions(&id, &["👍".to_string()]);
        assert!(wait(&dc, &|| dc.group(&id).is_some_and(|g| g.react_list == vec!["👍".to_string()])), "Carol never heard the channel's reactions");
        dc.react(&chat, &post, "😂");
        for _ in 0..3 {
            da.fetch_once();
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
        assert!(!a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == post && m.peer_react == "😂"), "a reaction outside the list was taken");
        dc.react(&chat, &post, "👍");
        assert!(wait(&da, &|| a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == post && m.peer_react == "👍")), "Carol's 👍 never came");
        let _ = std::fs::remove_dir_all(&root);
    }

    /// A GROUP'S LINK, LIVE: Alice makes a group of Bob and hands out its link; Carol, who never met Alice, opens it -- she meets
    /// Alice's card and asks to join by the invitation's road; Alice adds her, Carol holds the group and writes into it, Bob reads
    /// her there; Alice takes Bob out, and the same link does not bring him back. Run with --ignored and MONTANA_LIVE=1.
    #[test]
    #[ignore]
    fn a_groups_link_brings_a_stranger_in() {
        let root = std::env::temp_dir().join(format!("montana-group-link-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (a, b, c) = (person(&root, "Alice"), person(&root, "Bob"), person(&root, "Carol"));
        let (da, db, dc) = (desk(&a), desk(&b), desk(&c));
        let meet = |p: &Person, link: &str| -> String {
            for _ in 0..10 {
                if let meeting::Outcome::Opened(r) = meeting::meet(&p.vault, &p.book, link) {
                    return r;
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
            }
            panic!("no meeting")
        };
        let card = (Card { vault: &a.vault }).offer_permanent("Alice").unwrap();
        let rb = meet(&b, &card);
        db.send(&rb, "Привет от Боба");
        assert!(wait(&da, &|| a.book.all().iter().any(|x| !x.msgs.is_empty())), "Alice did not hear Bob");
        let pb = a.book.all().into_iter().find(|x| !x.msgs.is_empty()).unwrap().reference;
        da.send(&pb, "Привет!");
        assert!(wait(&db, &|| meeting::first(&b.vault, &rb).is_none()));
        let chat = da.group_create("По ссылке", std::slice::from_ref(&pb)).unwrap();
        let id = chat.strip_prefix("grp:").unwrap().to_string();
        assert!(wait(&db, &|| db.group(&id).is_some()), "Bob never got the invitation");

        let link = da.group_link(&id).unwrap();
        assert_eq!(join_mark(&link).map(|x| x.0), Some(id.clone()));
        // Bob writes before Carol comes; the group shows its past to new members (iOS G.4)
        let before = db.draft(&chat, "До Кэрол", "", "");
        assert!(db.post(&chat, &before));
        assert!(wait(&da, &|| a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == before)), "Alice never heard Bob");
        da.group_set_history(&id, true);
        // the link asks Alice first: Carol waits among the requests until Alice adds her (iOS «Request Admin Approval»)
        da.group_set_approval(&id, true);
        let rc = meet(&c, &link);
        dc.group_join(&rc, &id, &join_mark(&link).unwrap().1);
        assert!(wait(&da, &|| da.group(&id).is_some_and(|g| g.requests.len() == 1)), "Carol's request never waited at Alice's");
        assert_eq!(da.group(&id).unwrap().members.len(), 1, "a request is no member");
        let pc = da.group(&id).unwrap().requests[0].pipe.clone();
        assert!(da.group_approve(&id, &pc), "Alice could not add Carol");
        assert!(da.group(&id).is_some_and(|g| g.members.len() == 2 && g.requests.is_empty()), "Alice never added Carol by the link");
        assert!(a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.text.contains("\"e\":\"joined\"")), "«joined by the link» stands");
        assert!(wait(&dc, &|| dc.group(&id).is_some_and(|g| g.owner == rc)), "Carol never held the group");
        assert!(wait(&dc, &|| c.book.chat(&chat).is_some_and(|x| x.msgs.iter().any(|m| m.mid == before && m.text == "До Кэрол"))),
                "Carol never read the group's past");
        assert_eq!(c.book.chat(&chat).unwrap().unread, 0, "the past is read already");
        let mid = dc.draft(&chat, "Я по ссылке", "", "");
        assert!(dc.post(&chat, &mid));
        assert!(wait(&da, &|| a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == mid)), "Alice never heard Carol");
        assert!(wait(&db, &|| b.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == mid)), "Bob never read Carol in the group");

        // Bob named an administrator who invites holds the group's link, as Alice handed it out
        let bob_seat = da.group(&id).unwrap().members.iter().find(|m| m.pipe == pb).unwrap().seat.clone();
        da.group_set_admin(&id, &bob_seat, true, &[], "");
        assert!(wait(&db, &|| db.group_link(&id).as_deref() == Some(link.as_str())), "Bob never held the link");

        // one taken out does not come back by the link
        da.group_remove(&id, &bob_seat);
        assert!(wait(&db, &|| db.group(&id).is_some_and(|g| g.removed)), "Bob never heard he was taken out");
        db.group_join(&rb, &id, &join_mark(&link).unwrap().1);
        for _ in 0..4 {
            da.fetch_once();
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
        assert!(!da.group(&id).unwrap().members.iter().any(|m| m.pipe == pb), "the link brought back one taken out");
        let _ = std::fs::remove_dir_all(&root);
    }

    /// A GROUP'S RIGHTS, LIVE: Alice makes a group of Bob and Carol and takes words from its members -- Bob's letter is refused
    /// at Alice's and never reaches Carol; she gives words back with a slow mode of ten seconds -- Bob's second letter waits at
    /// Alice's until its interval, then comes; she names Bob an administrator, and Bob takes Carol out by his own right.
    /// Run with --ignored and MONTANA_LIVE=1.
    #[test]
    #[ignore]
    fn a_groups_rights_and_its_administrator() {
        let root = std::env::temp_dir().join(format!("montana-group-rights-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (a, b, c) = (person(&root, "Alice"), person(&root, "Bob"), person(&root, "Carol"));
        let (da, db, dc) = (desk(&a), desk(&b), desk(&c));
        let link = (Card { vault: &a.vault }).offer_permanent("Alice").unwrap();
        let meet = |p: &Person| -> String {
            for _ in 0..10 {
                if let meeting::Outcome::Opened(r) = meeting::meet(&p.vault, &p.book, &link) {
                    return r;
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
            }
            panic!("no meeting")
        };
        let (rb, rc) = (meet(&b), meet(&c));
        db.send(&rb, "Привет от Боба");
        dc.send(&rc, "Привет от Кэрол");
        assert!(wait(&da, &|| a.book.all().iter().filter(|x| !x.msgs.is_empty()).count() == 2), "Alice did not hear both");
        let pipes: Vec<String> = a.book.all().into_iter().filter(|x| !x.msgs.is_empty()).map(|x| x.reference).collect();
        for p in &pipes {
            da.send(p, "Привет!");
        }
        assert!(wait(&db, &|| meeting::first(&b.vault, &rb).is_none()));
        assert!(wait(&dc, &|| meeting::first(&c.vault, &rc).is_none()));
        let chat = da.group_create("Правила", &pipes).unwrap();
        let id = chat.strip_prefix("grp:").unwrap().to_string();
        assert!(wait(&db, &|| db.group(&id).is_some()) && wait(&dc, &|| dc.group(&id).is_some()), "the invitations never came");

        // words taken from the members: Bob's machine says why, and Alice's refuses the letter that goes anyway
        da.group_set_rights(&id, &["tx".to_string()], 0);
        assert!(wait(&db, &|| db.group(&id).is_some_and(|g| g.barred == ["tx"])), "Bob never heard the rights");
        assert_eq!(db.group_refusal(&id, "можно?").as_deref(), Some("tx"));
        assert_eq!(db.group_refusal(&id, &format!("{}🔥", marks::STICKER)), None, "a sticker is not words");
        let refused = db.draft(&chat, "Запрещённое слово", "", "");
        db.post(&chat, &refused);
        for _ in 0..4 {
            da.fetch_once();
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
        assert!(!a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == refused), "the owner took a letter past the rights");

        // words back, with a slow mode of ten seconds: the second letter waits for its interval
        da.group_set_rights(&id, &[], 10);
        assert!(wait(&db, &|| db.group(&id).is_some_and(|g| g.barred.is_empty() && g.slow == 10)), "Bob never heard the slow mode");
        let (m1, m2) = (db.draft(&chat, "Первое", "", ""), db.draft(&chat, "Второе", "", ""));
        assert!(db.post(&chat, &m1) && db.post(&chat, &m2));
        assert!(wait(&da, &|| a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == m1)), "the first letter never came");
        let first_at = crate::wire::now_ms();
        assert!(wait(&da, &|| { da.group_retry(); a.book.chat(&chat).unwrap().msgs.iter().any(|m| m.mid == m2) }), "the second letter never came");
        assert!(crate::wire::now_ms() - first_at >= 5_000, "the second letter did not wait for its interval");

        // Bob an administrator who may ban: Carol taken out by his hand
        let bob = da.group(&id).unwrap().members.iter().find(|m| m.pipe == pipes.iter().find(|p| a.book.chat(p).is_some_and(|c| c.name == "Bob")).cloned().unwrap()).unwrap().seat.clone();
        let carol = da.group(&id).unwrap().members.iter().find(|m| m.seat != bob).unwrap().seat.clone();
        da.group_set_admin(&id, &bob, true, &["dm".to_string()], "Смотритель");
        assert!(wait(&db, &|| db.group(&id).is_some_and(|g| g.admins.contains(&bob) && g.ranks.get(&bob).map(String::as_str) == Some("Смотритель"))),
                "Bob never heard he is an administrator");
        assert!(admin_can(&db.group(&id).unwrap(), &bob, "bu") && !admin_can(&db.group(&id).unwrap(), &bob, "dm"), "the right left out stays out");
        db.group_kick(&id, &carol);
        assert!(wait(&da, &|| !da.group(&id).unwrap().members.iter().any(|m| m.seat == carol)), "Alice never took Carol out at Bob's word");
        assert!(wait(&dc, &|| dc.group(&id).is_some_and(|g| g.removed)), "Carol never heard she was taken out");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_letter_names_me_where_my_name_ends_a_word() {
        assert!(mentions_me("Борис: @Алиса Тест, глянь", "Алиса Тест"));
        assert!(mentions_me("@ALICE!", "alice") && mentions_me("эй @alice", "Alice"));
        assert!(!mentions_me("@Alex, привет", "Al") && !mentions_me("alice без собаки", "alice") && !mentions_me("@кто", ""));
    }

    #[test]
    fn a_word_asks_the_rights_ios_names() {
        assert_eq!(rights_asked("привет"), ["tx"]);
        assert_eq!(rights_asked("смотри https://montana.quest"), ["tx", "ln"]);
        assert_eq!(rights_asked(&format!("{}🔥", marks::STICKER)), ["gf"]);
        assert_eq!(rights_asked(&format!("{}{}", marks::MEDIA, r#"{"k":"img","n":"a.jpg"}"#)), ["ph"]);
        assert_eq!(rights_asked(&format!("{}{}", marks::MEDIA, r#"{"k":"vid","r":true}"#)), ["rv"]);
        assert_eq!(rights_asked(&format!("{}{}", marks::MEDIA, r#"{"k":"doc","n":"song.MP3"}"#)), ["mu"]);
        assert_eq!(rights_asked(&format!("{}{}", marks::MEDIA, r#"{"k":"doc","n":"x.pdf","cap":"http://a.org/x"}"#)), ["fl", "ln"]);
        assert_eq!(rights_asked(&format!("{}{}", marks::REACT, "{}")), ["re"]);
        assert!(rights_asked(&format!("{}mid:t1-A", marks::DELETE)).is_empty());
        let mut g = Group { id: "g".into(), kind: "g".into(), barred: vec!["tx".into()], admins: vec!["ab".into()], ..Default::default() };
        g.admin_taken.insert("ab".into(), vec!["bu".into()]);
        assert!(!allows(&g, "cd", "слово") && allows(&g, "cd", &format!("{}🔥", marks::STICKER)));
        assert!(allows(&g, "ab", "слово") && allows(&g, "0", "слово"), "the owner and its administrators keep every right");
        assert!(admin_can(&g, "0", "bu") && !admin_can(&g, "ab", "bu") && admin_can(&g, "ab", "dm") && !admin_can(&g, "cd", "dm"));
        let mut h = Group::default();
        take_rights(&json!({ "ax": { "ab": ["dm", "zz"], "!!": ["dm"] }, "rk": { "ab": "  Очень длинный титул администратора " }, "bn": ["tx", "zz"], "sw": 99999 }), &mut h);
        assert_eq!(h.admin_taken.get("ab"), Some(&vec!["dm".to_string()]));
        assert_eq!(h.ranks.get("ab").map(|r| r.chars().count()), Some(16));
        assert_eq!((h.barred.clone(), h.slow), (vec!["tx".to_string()], 3600));
    }

    #[test]
    fn a_groups_mark_is_read_from_its_link() {
        let g = "0123456789abcdef0123456789abcdef";
        let m = "fedcba9876543210fedcba9876543210";
        assert_eq!(join_mark(&format!("https://montana.quest/perp/AAAA?jg={g}.{m}")), Some((g.into(), m.into())));
        assert_eq!(join_mark(&format!("https://montana.quest/perp/AAAA?x=1&jg={g}.{m}#t")), Some((g.into(), m.into())));
        assert!(join_mark(&format!("https://montana.quest/perp/AAAA?jg={g}")).is_none());
        assert!(join_mark(&format!("https://montana.quest/perp/AAAA?jg={}.{m}", g.to_uppercase())).is_none());
    }

    #[test]
    fn a_groups_face_and_the_persons_tag_are_ios_own() {
        let fc = wire::b64(&[0xFF, 0xD8, 1, 2, 3]);
        assert_eq!(face_of(&fc), Some(vec![0xFF, 0xD8, 1, 2, 3]));
        assert!(face_of(&wire::b64(b"GIF89a")).is_none() && face_of(&"A".repeat(FACE_LIMIT + 4)).is_none());
        assert_eq!(face_tag("abcdefghijklmnopqrstuvwxyz"), "26-klmnopqrstuvwxyz");
        let o = json!({ "t": "say", "g": "g1", "id": "t1-A", "s": "ab", "tx": "привет" });
        assert_eq!(tag_text(&o), "say\0t1-A\0\0ab\0\0привет");
        let (key, secret) = ([3u8; 32], [4u8; 32]);
        let au = wire::author_tag(&key, &secret, "g1", &tag_text(&o));
        assert!(wire::author_holds(&au, Some(&key), &secret, "g1", &tag_text(&o)), "the person's own word is told by its tag");
        let mut forged = o.clone();
        forged["tx"] = json!("иное");
        assert!(!wire::author_holds(&au, Some(&key), &secret, "g1", &tag_text(&forged)), "another's words under the tag are not mine");
    }
}
