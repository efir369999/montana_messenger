//! PRESENCE (iOS MontanaE2E presence words + MontanaWakePush's signal lane; Android Presence.kt): short-lived words that
//! never stand in a box -- «in my chat» (WA:), «in the app» (AP:), «typing» (TY:) -- sealed under the pipe's minute key and
//! posted on the signal lane (/signal); the open chat listens on a long poll (/signal-fetch); the list learns «last seen»
//! from the lane's last words (/signal-last). Each word carries the moment it was said, and lives 45 s from it (typing 5).
//! Plain: twin ‖ 0 ‖ "chat" ‖ 0 ‖ raw DEFLATE(word). A word older than one held for the same kind changes nothing.

use crate::book::Book;
use crate::post::marks;
use crate::wire::{self, b64, body_key, conv_w, sha, sub_id, unb64};
use crate::{crypto, doors, media};
use serde::Serialize;
use serde_json::json;
use std::collections::HashMap;
use std::sync::Mutex;

pub const TYPING: &str = "\u{200B}\u{200B}TY:";
pub const WATCH: &str = "\u{200B}\u{200B}WA:";
pub const APP: &str = "\u{200B}\u{200B}AP:";
const LIFE_MS: i64 = 45_000;
const TYPING_MS: i64 = 5_000;
const TYPING_WORD_MS: i64 = 7_000;

/// wireTag (iOS MontanaDeliveryEngine 500-506): the first four bytes of SHA-256 as a big-endian number, in decimal; "0" for
/// nothing.
pub fn wire_tag(b: &[u8]) -> String {
    if b.is_empty() {
        return "0".into();
    }
    let h = sha(&[b]);
    u32::from_be_bytes([h[0], h[1], h[2], h[3]]).to_string()
}

pub fn about_tag(bio: &str, link: &str) -> String {
    if bio.is_empty() && link.is_empty() { "0".into() } else { wire_tag(format!("{bio}\n{link}").as_bytes()) }
}

/// What one correspondent's presence is, as the window draws it.
#[derive(Serialize, Default, Clone)]
pub struct Seen {
    /// "typing" | "watching" | "inchat" | "online" | "gone" | "seen" | "none"
    pub state: String,
    /// the moment last seen (ms), for "seen"
    pub at: i64,
    /// they hide the exact moment: coarse classes only
    pub hides: bool,
    /// THEIR LIVE WORDS (iOS LiveDraftState): what their field holds now, shown while both have the chat's Money Flow on
    pub draft: String,
    pub draft_rm: String,
    /// where their caret stands in it (-1: at the end)
    pub draft_c: i64,
}

#[derive(Default, Clone)]
struct Peer {
    online_until: i64,
    chat_until: i64,
    typing_until: i64,
    /// the moments of the newest word held per kind ('c' chat, 'a' app): an older word changes nothing (liveWordMoves)
    chat_at: i64,
    app_at: i64,
    seen_at: i64,
    gone_at: i64,
    hides: bool,
    /// the doors they named (uppercase hosts) and when
    doors: Vec<String>,
    doors_at: i64,
    last_echo: i64,
    last_heal: i64,
    /// what their last word said of their wall's version and of my page's ground they hold (iOS «W», «G»)
    wall_said: Option<String>,
    ground_said: Option<String>,
    /// their live words (iOS LiveDraftState): the text, the letter they answer, the newest word's own moment
    draft: String,
    draft_rm: String,
    draft_c: i64,
    draft_n: i64,
}

/// THE MONEY FLOW IS A CHAT'S OWN (iOS MTMoneyFlow, the author's word 04.10.2026): the chats whose coin is turned on this machine.
/// Live words are said and shown in them alone.
static FLOWS: Mutex<Option<std::collections::HashSet<String>>> = Mutex::new(None);
pub fn flows_load(list: Vec<String>) {
    *FLOWS.lock().unwrap() = Some(list.into_iter().collect());
}
pub fn flow_on(r: &str) -> bool {
    !r.is_empty() && FLOWS.lock().unwrap().as_ref().is_some_and(|f| f.contains(r))
}
pub fn set_flow(r: &str, on: bool) -> Vec<String> {
    let mut g = FLOWS.lock().unwrap();
    let f = g.get_or_insert_with(Default::default);
    if on { f.insert(r.to_string()); } else { f.remove(r); }
    let mut out: Vec<String> = f.iter().cloned().collect();
    out.sort();
    out
}

#[derive(Default)]
pub struct Presence {
    peers: Mutex<HashMap<String, Peer>>,
    said: Mutex<i64>,
    /// I type: «watching» shows while they are in my chat and I write (my typing lives 6 s)
    my_typing_until: Mutex<i64>,
    /// WHO TYPES IN A GROUP (iOS MTGroupTyping): each group chat's seats by the moment their word landed, alive the typing life
    groups: Mutex<HashMap<String, HashMap<String, i64>>>,
    /// the moments the owner last threw a member's typing on: once in two seconds a member (iOS typingThrown)
    thrown: Mutex<HashMap<String, i64>>,
    /// the group chats whose typing moved since the window was last told
    moved: Mutex<Vec<String>>,
    /// what my word says after my bio's tag (iOS heldTail «W…G…»): my wall's version and the ground of theirs I hold
    tail: Mutex<Option<Tail>>,
}

type Tail = Box<dyn Fn(&str) -> String + Send + Sync>;

/// THE TAGS AFTER THE BIO'S (iOS wallHeard / groundHeld): «W» and its digits stand after the name's digits and the bio's, «G» right
/// after the wall's; a build before them names nothing.
pub fn held_after(tail: &str) -> (Option<String>, Option<String>) {
    let digits = |s: &str| -> String { s.chars().take_while(|c| c.is_ascii_digit()).collect() };
    let Some(i) = tail.find('N') else { return (None, None) };
    let mut rest = &tail[i + 1..];
    rest = &rest[digits(rest).len()..];
    if let Some(r) = rest.strip_prefix('A') {
        rest = &r[digits(r).len()..];
    }
    let Some(r) = rest.strip_prefix('W') else { return (None, None) };
    let w = digits(r);
    if w.is_empty() {
        return (None, None);
    }
    let rest = &r[w.len()..];
    let g = rest.strip_prefix('G').map(digits).filter(|g| !g.is_empty());
    (Some(w), g)
}

fn now() -> i64 {
    wire::now_ms()
}

/// The hosts of my doors, uppercase (no lowercase h or f may stand after the digit: iOS reads them as marks).
fn my_hosts() -> Vec<String> {
    doors::all().iter().filter_map(|d| d.split("://").nth(1)).filter_map(|h| h.split('/').next()).map(|h| h.to_uppercase()).collect()
}

/// The word's moment: the first T and ten digits, a dot and three (iOS presenceMoment).
fn moment(text: &str) -> Option<i64> {
    let (rest, secs) = text.match_indices('T').find_map(|(i, _)| {
        let rest = &text[i + 1..];
        let secs: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
        (9..=11).contains(&secs.len()).then_some((rest, secs))
    })?;
    let s: i64 = secs.parse().ok()?;
    let after = &rest[secs.len()..];
    let ms = after.strip_prefix('.').and_then(|m| m.get(..3)).and_then(|m| m.parse::<i64>().ok()).unwrap_or(0);
    Some(s * 1000 + ms)
}

impl Presence {
    /// A TYPING WORD LANDED IN A GROUP (iOS MTGroupTyping.heard): the seat types for the typing life from now.
    pub fn group_typed(&self, chat: &str, seat: &str) {
        self.groups.lock().unwrap().entry(chat.to_string()).or_default().insert(seat.to_string(), now());
        self.group_moved(chat);
    }

    /// The seat's letter came: it types no more (iOS stopped).
    pub fn group_stopped(&self, chat: &str, seat: &str) {
        let gone = self.groups.lock().unwrap().get_mut(chat).and_then(|s| s.remove(seat)).is_some();
        if gone {
            self.group_moved(chat);
        }
    }

    fn group_moved(&self, chat: &str) {
        let mut m = self.moved.lock().unwrap();
        if !m.iter().any(|c| c == chat) {
            m.push(chat.to_string());
        }
    }

    /// The group chats whose typing moved since last asked.
    pub fn groups_moved(&self) -> Vec<String> {
        std::mem::take(&mut *self.moved.lock().unwrap())
    }

    /// Who types in a group now, the earliest first (iOS line).
    pub fn group_typing(&self, chat: &str) -> Vec<String> {
        let t = now();
        let mut all = self.groups.lock().unwrap();
        let Some(seats) = all.get_mut(chat) else { return vec![] };
        seats.retain(|_, at| t - *at < TYPING_MS);
        let mut v: Vec<(String, i64)> = seats.iter().map(|(s, at)| (s.clone(), *at)).collect();
        v.sort_by_key(|x| x.1);
        v.into_iter().map(|x| x.0).collect()
    }

    /// Whether the owner throws this member's typing on now: once in two seconds a member, whatever it sends (iOS I-15).
    pub fn throw_due(&self, key: &str) -> bool {
        let t = now();
        let mut m = self.thrown.lock().unwrap();
        if t - m.get(key).copied().unwrap_or(0) < 2_000 {
            return false;
        }
        m.insert(key.to_string(), t);
        true
    }

    /// SAID (iOS saidTail): T<seconds>.<ms>, strictly increasing across every word this device says.
    pub fn said_tail(&self) -> String {
        let mut last = self.said.lock().unwrap();
        *last = (*last + 1).max(now());
        format!("T{}.{:03}", *last / 1000, *last % 1000)
    }

    /// What I hold of them (iOS heldTail without the wall): F their face, N their declared name, A their words about themselves.
    fn held(&self, book: &Book, faces: &media::Store, r: &str) -> String {
        let Some(c) = book.chat(r) else { return String::new() };
        let face = faces.get(r).unwrap_or_default();
        let tail = self.tail.lock().unwrap().as_ref().map(|f| f(r)).unwrap_or_default();
        format!("F{}N{}A{}{tail}", wire_tag(&face), wire_tag(c.name.trim().as_bytes()), about_tag(&c.peer_bio, &c.peer_link))
    }

    /// What follows the bio's tag in my words to each correspondent (set once, by the wall's walk).
    pub fn set_tail(&self, f: Tail) {
        *self.tail.lock().unwrap() = Some(f);
    }

    /// What their last word said of their wall's version and of my page's ground they hold.
    pub fn held_said(&self, r: &str) -> (Option<String>, Option<String>) {
        self.peers.lock().unwrap().get(r).map(|p| (p.wall_said.clone(), p.ground_said.clone())).unwrap_or_default()
    }

    pub fn word_watch(&self, book: &Book, faces: &media::Store, r: &str, open: bool) -> String {
        format!("{WATCH}{}{}{}@{}", if open { "1" } else { "0" }, self.said_tail(), self.held(book, faces, r), my_hosts().join(","))
    }

    pub fn word_app(&self, book: &Book, faces: &media::Store, r: &str, open: bool) -> String {
        format!("{APP}{}{}{}", if open { "1" } else { "0" }, self.said_tail(), self.held(book, faces, r))
    }

    /// MY LIVE WORDS (iOS sendDraftWord): what my field holds, its caret, the letter it answers, the word's own moment, my doors;
    /// an empty text ends the draft. A checkpoint (`ck`, the chat closed or the window hid) freezes their bubble at the field's state
    /// and is no keystroke.
    pub fn word_draft(&self, text: &str, caret: i64, rm: &str, checkpoint: bool) -> String {
        let n = {
            let mut last = self.said.lock().unwrap();
            *last = (*last + 1).max(now());
            *last
        };
        let mut body = serde_json::json!({ "t": text, "c": caret, "n": n });
        if checkpoint {
            body["ck"] = serde_json::json!(1);
        }
        if !rm.is_empty() {
            body["rm"] = serde_json::json!(rm);
        }
        let d = my_hosts().join(",");
        if !d.is_empty() {
            body["d"] = serde_json::json!(d);
        }
        format!("{}{}", marks::DRAFT, wire::b64(body.to_string().as_bytes()))
    }
    /// A LETTER OF THEIRS ENDS THE DRAFT THAT BECAME IT (iOS ChatStore.place): the words stand as a letter now, and every word of
    /// that draft was said before it -- none still on the road may stand again. The landing is stamped by the nodes' clock, never
    /// below a moment of theirs already held.
    pub fn landed(&self, r: &str) {
        if let Some(p) = self.peers.lock().unwrap().get_mut(r) {
            p.draft.clear();
            p.draft_rm.clear();
            p.draft_c = -1;
            p.draft_n = p.draft_n.max(crate::person::node_now_ms().unwrap_or_else(now));
        }
    }
    /// My Money Flow of the chat went off: their live words leave the screen (iOS dropLive).
    pub fn drop_live(&self, r: &str) {
        if let Some(p) = self.peers.lock().unwrap().get_mut(r) {
            p.draft.clear();
            p.draft_rm.clear();
            p.draft_c = -1;
        }
    }

    pub fn word_typing(&self) -> String {
        *self.my_typing_until.lock().unwrap() = now() + 6_000;
        format!("{TYPING}{}", self.said_tail())
    }

    /// THE LANE'S POST (iOS MontanaWakePush.signal): sealed under the pipe's key of this minute; to the door both sides
    /// compute when they named theirs within a minute, else to every door.
    pub fn post(&self, book: &Book, twin: &str, r: &str, word: &str) -> bool {
        let Some(secret) = book.secret(r) else { return false };
        let plain = [twin.as_bytes(), &[0], b"chat", &[0], &miniz_oxide::deflate::compress_to_vec(word.as_bytes(), 6)].concat();
        let Some(env) = crypto::seal(&body_key(&secret, wire::minute()), &plain) else { return false };
        let cw = conv_w(&secret, wire::day());
        let body = json!({ "conv": cw, "from_id": sub_id(&cw, twin), "env": b64(&env) });
        let named = self.peers.lock().unwrap().get(r).filter(|p| now() - p.doors_at < 60_000).map(|p| p.doors.clone());
        let all = doors::all();
        let chosen: Vec<String> = match named {
            Some(n) => all.iter().filter(|d| n.iter().any(|h| d.to_uppercase().contains(h.as_str()))).take(1).cloned().collect(),
            None => vec![],
        };
        let targets = if chosen.is_empty() { all } else { chosen };
        let mut ok = false;
        let mut said = vec![];
        for d in targets {
            let code = doors::post_at(&d, "/signal", &body, 5_000).0;
            said.push(format!("{}={code}", d.split('/').nth(2).unwrap_or("")));
            ok |= code == 200;
        }
        crate::trace_line(&format!("lane_post chat={} word={} doors={}", &r[..r.len().min(10)], word.chars().take(12).collect::<String>().escape_debug(), said.join(",")));
        ok
    }

    /// A word off the lane, opened: (sender twin, epoch, the inflated bytes).
    pub fn open(secret: &[u8], env_b64: &str, at_ms: Option<i64>) -> Option<(String, String, Vec<u8>)> {
        let sealed = unb64(env_b64)?;
        let plain = match at_ms {
            Some(at) => wire::open_boxed(&sealed, secret, at / 1000)?,
            None => {
                let w = wire::minute();
                [w, w - 1, w + 1].iter().find_map(|m| wire::open(&body_key(secret, *m), &sealed))?
            }
        };
        let a = plain.iter().position(|&b| b == 0)?;
        let b = a + 1 + plain[a + 1..].iter().position(|&b| b == 0)?;
        let twin = String::from_utf8_lossy(&plain[..a]).into_owned();
        let epoch = String::from_utf8_lossy(&plain[a + 1..b]).into_owned();
        let body = miniz_oxide::inflate::decompress_to_vec(&plain[b + 1..]).ok()?;
        Some((twin, epoch, body))
    }

    /// THE LIVE WORD (iOS ChatStore 4282-4338, liveWordMoves): typing, in my chat, in the app, gone, hiding. Returns whether
    /// the ladder moved and whether to echo my AP:1 (a fresh WA:1).
    pub fn hear(&self, r: &str, text: &str, stamp_only: bool) -> (bool, bool) {
        let t = now();
        let said = moment(text);
        let at = said.unwrap_or(t).min(t);
        let mut peers = self.peers.lock().unwrap();
        let p = peers.entry(r.to_string()).or_default();
        p.seen_at = p.seen_at.max(at);
        let fresh = !stamp_only && t - at <= LIFE_MS;
        let mut echo = false;
        if let Some(rest) = text.strip_prefix(TYPING) {
            let _ = rest;
            if !stamp_only && t - at <= TYPING_WORD_MS && at >= p.chat_at {
                p.typing_until = at + TYPING_MS;
                p.chat_until = at + LIFE_MS;
                p.online_until = p.online_until.max(at + LIFE_MS);
                p.chat_at = at;
            }
            return (true, false);
        }
        if let Some(code) = text.strip_prefix(marks::DRAFT) {
            // THEIR LIVE WORDS (iOS handleLiveDraft): a word older than the one shown is an echo of the road; my own Money Flow
            // off -- their words show nothing here; a keystroke said now lights «typing…»
            let Some(j) = wire::unb64(code).and_then(|d| serde_json::from_slice::<serde_json::Value>(&d).ok()) else { return (false, false) };
            if let Some(d) = j["d"].as_str() {
                // the doors they ask (iOS notePeerDoor)
                p.doors = d.split(',').map(|h| h.trim().to_string()).filter(|h| !h.is_empty()).collect();
                p.doors_at = t;
            }
            if let Some(n) = j["n"].as_i64() {
                if n <= p.draft_n {
                    return (false, false);
                }
                p.draft_n = n;
            }
            if !flow_on(r) {
                return (false, false);
            }
            p.draft = j["t"].as_str().unwrap_or("").chars().take(4500).collect();
            p.draft_rm = j["rm"].as_str().unwrap_or("").chars().take(128).collect();
            p.draft_c = j["c"].as_i64().unwrap_or(-1);
            let state = ["ck", "rl", "rb", "ab", "al", "at", "rq"].iter().any(|k| !j[*k].is_null());
            let said_at = j["n"].as_i64().unwrap_or(at);   // a keystroke is a word said now by its own moment
            if !p.draft.is_empty() && !state && !stamp_only && t - said_at <= TYPING_WORD_MS {
                p.typing_until = at + TYPING_MS;
                p.chat_until = p.chat_until.max(at + LIFE_MS);
                p.online_until = p.online_until.max(at + LIFE_MS);
            }
            return (true, false);
        }
        let (word, kind) = if let Some(w) = text.strip_prefix(WATCH) { (w, 'c') } else if let Some(w) = text.strip_prefix(APP) { (w, 'a') } else { return (false, false) };
        let tail = word.get(1..).unwrap_or("");
        let open = word.starts_with('1');
        if let Some(at_sign) = word.find('@') {
            p.doors = word[at_sign + 1..].split(',').map(|h| h.trim().to_string()).filter(|h| !h.is_empty()).collect();
            p.doors_at = t;
        }
        p.hides = tail.split('@').next().unwrap_or("").contains('h');
        // what a word proves of its build is read from every word, late ones too (iOS heardCapable)
        let held = tail.split('@').next().unwrap_or("");
        let (w, g) = held_after(held);
        // the balance and the Global Level after the ground's digits (iOS heardCoins / heardLevel), for the board of the people
        if g.is_some() {
            crate::coinboard::hear_later(r, held, at as f64 / 1000.0);
        }
        if w.is_some() {
            p.wall_said = w;
            p.ground_said = g;
        }
        if kind == 'a' && tail.starts_with('B') {
            p.gone_at = at;
            p.online_until = 0;
            p.chat_until = 0;
            p.typing_until = 0;
            return (true, false);
        }
        if kind == 'a' && at > p.gone_at {
            p.gone_at = 0;
        }
        if !fresh {
            return (true, false);
        }
        match kind {
            'c' => {
                if at < p.chat_at {
                    return (false, false);
                }
                p.chat_at = at;
                if open {
                    p.chat_until = at + LIFE_MS;
                    p.online_until = p.online_until.max(at + LIFE_MS);
                    if t - p.last_echo >= 800 {
                        p.last_echo = t;
                        echo = true;
                    }
                } else {
                    p.chat_until = 0;
                    p.typing_until = 0;
                }
            }
            _ => {
                if at < p.app_at {
                    return (false, false);
                }
                p.app_at = at;
                if open {
                    p.online_until = at + LIFE_MS;
                } else {
                    p.online_until = 0;
                    p.chat_until = 0;
                }
            }
        }
        (true, echo)
    }

    /// heardHeld (iOS E2E 662-700): their word says what they hold of me; a stale face, name or bio is said again, at most
    /// once a minute. The tags of mine to compare with.
    pub fn stale(&self, r: &str, text: &str, my_face: &str, my_name: &str, my_about: &str) -> Option<(bool, bool, bool)> {
        let tail = text.strip_prefix(WATCH).or_else(|| text.strip_prefix(APP))?;
        let tail = tail.split('@').next().unwrap_or("");
        let num = |k: char| -> Option<String> {
            let i = tail.find(k)?;
            Some(tail[i + 1..].chars().take_while(|c| c.is_ascii_digit()).collect())
        };
        let (f, n) = (num('F')?, num('N')?);
        let a = num('A');
        let off = (f != my_face, n != my_name, a.is_some_and(|a| a != my_about));
        if !(off.0 || off.1 || off.2) {
            return None;
        }
        let mut peers = self.peers.lock().unwrap();
        let p = peers.entry(r.to_string()).or_default();
        if now() - p.last_heal < 60_000 {
            return None;
        }
        p.last_heal = now();
        Some(off)
    }

    /// THE LADDER (iOS ChatStore.presenceWord): typing > watching > in chat > online > gone > last seen.
    pub fn seen(&self, r: &str) -> Seen {
        let t = now();
        let peers = self.peers.lock().unwrap();
        let Some(p) = peers.get(r) else { return Seen { state: "none".into(), ..Default::default() } };
        let state = if p.typing_until > t {
            "typing"
        } else if p.chat_until > t && *self.my_typing_until.lock().unwrap() > t {
            "watching"
        } else if p.chat_until > t {
            "inchat"
        } else if p.online_until > t {
            "online"
        } else if p.gone_at > 0 {
            "gone"
        } else if p.seen_at > 0 {
            "seen"
        } else {
            "none"
        };
        let (draft, draft_rm, draft_c) = if flow_on(r) { (p.draft.clone(), p.draft_rm.clone(), p.draft_c) } else { (String::new(), String::new(), -1) };
        Seen { state: state.into(), at: p.seen_at, hides: p.hides, draft, draft_rm, draft_c }
    }

    pub fn live(&self, r: &str) -> bool {
        matches!(self.seen(r).state.as_str(), "typing" | "watching" | "inchat" | "online")
    }

    /// THE SWEEP (iOS /signal-last): the newest lane word of every correspondence, yesterday's and today's -- stamps only.
    pub fn sweep(&self, book: &Book, twin: &str) -> bool {
        let mut q = vec![];
        let mut secrets: HashMap<String, (String, Vec<u8>)> = HashMap::new();
        let d0 = wire::day();
        for r in book.refs() {
            let Some(s) = book.secret(&r) else { continue };
            for d in [d0 - 1, d0] {
                let cw = conv_w(&s, d);
                q.push(json!({ "conv": cw, "from_id": sub_id(&cw, twin) }));
                secrets.insert(cw, (r.clone(), s.clone()));
            }
        }
        let mut moved = false;
        for chunk in q.chunks(128) {
            for door in doors::all() {
                let (code, v) = doors::post_at(&door, "/signal-last", &json!({ "q": chunk }), 6_000);
                if code != 200 {
                    continue;
                }
                for l in v.as_ref().and_then(|v| v["last"].as_array()).cloned().unwrap_or_default() {
                    let (Some(cw), Some(env), Some(at)) = (l["conv"].as_str(), l["env"].as_str(), l["at"].as_i64()) else { continue };
                    let Some((r, s)) = secrets.get(cw) else { continue };
                    if let Some((_, epoch, body)) = Self::open(s, env, Some(at * 1000)) {
                        if epoch == "chat" {
                            moved |= self.hear(r, &String::from_utf8_lossy(&body), true).0;
                        }
                    }
                }
            }
        }
        moved
    }

    /// One long poll of the lane of a correspondence (iOS /signal-fetch): the words the others said since; «box» says a letter
    /// waits in the box. The words, opened: (epoch, bytes); and whether the box called.
    pub fn listen(book: &Book, twin: &str, r: &str, dev: &str) -> Option<(Vec<Opened>, bool)> {
        let secret = book.secret(r)?;
        let cw = conv_w(&secret, wire::day());
        let tag = crate::wire::hex(&sha(&[b"mt-lane-dev\0", dev.as_bytes(), b"\0", cw.as_bytes()])[..8]);
        let body = json!({ "conv": cw, "from_id": sub_id(&cw, twin), "wait": 12, "dev": tag });
        let door = doors::all().into_iter().next()?;
        let (code, v) = doors::post_at(&door, "/signal-fetch", &body, 15_000);
        crate::trace_line(&format!("lane_fetch chat={} door={} code={code} envs={}", &r[..r.len().min(10)], door.split('/').nth(2).unwrap_or(""),
            v.as_ref().and_then(|v| v["envs"].as_array()).map(|a| a.len()).unwrap_or(0)));
        if code != 200 {
            return None;
        }
        let mut out = vec![];
        let mut boxed = false;
        for e in v.as_ref().and_then(|v| v["envs"].as_array()).cloned().unwrap_or_default() {
            let Some(e) = e.as_str() else { continue };
            if e == "box" {
                boxed = true;
                continue;
            }
            if let Some((_, epoch, body)) = Self::open(&secret, e, None) {
                out.push((epoch, body));
            }
        }
        Some((out, boxed))
    }
}

type Opened = (String, Vec<u8>);

/// The words of the wire a lane carries never land as letters of the feed.
pub fn is_lane_word(t: &str) -> bool {
    t.starts_with(TYPING) || t.starts_with(WATCH) || t.starts_with(APP) || t.starts_with(marks::DRAFT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_tags_and_the_deflate_agree_with_ios() {
        assert_eq!(wire_tag(b"Alice"), "1002770530");
        assert_eq!(wire_tag(b"0r"), "3246493016");
        assert_eq!(wire_tag(b""), "0");
        // a word iOS deflated (raw, level 5) inflates here
        let ios = crate::wire::unhex("7bd4d0fda8a13b24d22ac4d0dcd2c8c8c4d2c0c040cfd0c81800").unwrap();
        assert_eq!(miniz_oxide::inflate::decompress_to_vec(&ios).unwrap(), "\u{200B}\u{200B}TY:T1792249000.123".as_bytes());
        // and a word deflated here has no zlib header
        let mine = miniz_oxide::deflate::compress_to_vec(b"\xE2\x80\x8B\xE2\x80\x8BWA:1T1792249000.123", 6);
        assert_ne!(&mine[..2], &[0x78, 0x9C]);
        assert_eq!(moment("\u{200B}\u{200B}TY:T1792249000.123"), Some(1_792_249_000_123));
    }

    #[test]
    fn a_word_lives_from_its_moment_and_an_older_one_changes_nothing() {
        let p = Presence::default();
        let t = now();
        let at = |ms: i64| format!("T{}.{:03}", ms / 1000, ms % 1000);
        p.hear("r", &format!("{WATCH}1{}", at(t - 1000)), false);
        assert_eq!(p.seen("r").state, "inchat");
        p.hear("r", &format!("{WATCH}0{}", at(t - 5000)), false);
        assert_eq!(p.seen("r").state, "inchat", "an older «left» does not undo a newer «in chat»");
        p.hear("r", &format!("{WATCH}0{}", at(t)), false);
        assert_eq!(p.seen("r").state, "online");
        p.hear("r", &format!("{APP}0{}", at(t + 1)), false);
        assert_eq!(p.seen("r").state, "seen");
        p.hear("r", &format!("{APP}0B{}", at(t + 2)), false);
        assert_eq!(p.seen("r").state, "gone");
        p.hear("q", &format!("{APP}1{}", at(t - 60_000)), false);
        assert_eq!(p.seen("q").state, "seen", "a word older than its life only stamps");
    }

    #[test]
    fn a_group_types_by_its_seats_for_the_typing_life() {
        let p = Presence::default();
        p.group_typed("grp:g", "3");
        std::thread::sleep(std::time::Duration::from_millis(3)); // two moments, not one
        p.group_typed("grp:g", "1");
        assert_eq!(p.group_typing("grp:g"), vec!["3".to_string(), "1".to_string()], "the earliest first");
        assert_eq!(p.groups_moved(), vec!["grp:g".to_string()], "the chat is told once");
        assert!(p.groups_moved().is_empty());
        p.group_stopped("grp:g", "3");
        assert_eq!(p.group_typing("grp:g"), vec!["1".to_string()], "a letter ends its speaker's typing");
        p.groups.lock().unwrap().get_mut("grp:g").unwrap().insert("1".into(), now() - TYPING_MS);
        assert!(p.group_typing("grp:g").is_empty(), "the typing life is over");
        assert!(p.throw_due("g/1") && !p.throw_due("g/1"), "once in two seconds a member");
        assert!(p.throw_due("g/2"));
    }

    #[test]
    fn live_words_stand_in_the_money_flow_alone_and_a_letter_ends_them() {
        let (me, them) = (Presence::default(), Presence::default());
        let word = |t: &str, c: i64, rm: &str| me.word_draft(t, c, rm, false);
        let body = |w: &str| serde_json::from_slice::<serde_json::Value>(&wire::unb64(&w[marks::DRAFT.len()..]).unwrap()).unwrap();
        let w1 = word("прив", 4, "");
        assert_eq!(body(&w1)["t"], "прив");
        assert!(body(&w1)["rm"].is_null(), "no letter answered, no key");
        // my flow of the chat is off: their words show nothing
        them.hear("flow-a", &w1, false);
        assert_eq!(them.seen("flow-a").draft, "");
        set_flow("flow-a", true);
        let w2 = word("привет", 6, "t1-X");
        them.hear("flow-a", &w2, false);
        let s = them.seen("flow-a");
        assert_eq!((s.draft.as_str(), s.draft_c, s.draft_rm.as_str(), s.state.as_str()), ("привет", 6, "t1-X", "typing"));
        // an older word of the road is an echo
        them.hear("flow-a", &w1, false);
        assert_eq!(them.seen("flow-a").draft, "привет");
        // the letter landed: the draft leaves, and a word said before it never stands again
        them.landed("flow-a");
        assert_eq!(them.seen("flow-a").draft, "");
        them.hear("flow-a", &w2, false);
        assert_eq!(them.seen("flow-a").draft, "");
        // an empty word ends the draft; the flow turned off hides what stands
        std::thread::sleep(std::time::Duration::from_millis(3));   // a word said after the landing
        them.hear("flow-a", &word("ещё", 3, ""), false);
        assert_eq!(them.seen("flow-a").draft, "ещё");
        set_flow("flow-a", false);
        assert_eq!(them.seen("flow-a").draft, "");
        set_flow("flow-a", true);
        them.hear("flow-a", &word("", 0, ""), false);
        assert_eq!(them.seen("flow-a").draft, "");
        // the chat closed with words in the field: the bubble freezes there, and «typing…» is not lit by it
        let q = Presence::default();
        q.hear("flow-a", &me.word_draft("ушёл", 4, "", true), false);
        let s = q.seen("flow-a");
        assert_eq!(s.draft, "ушёл");
        assert_ne!(s.state, "typing", "a checkpoint is no keystroke");
        set_flow("flow-a", false);
    }
}
