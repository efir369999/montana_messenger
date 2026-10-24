//! THE POSTMAN (iOS MontanaDeliveryEngine + MontanaWakePush; Android Pipes.kt Post): a letter sealed under the pipe's body key
//! of this minute and boxed at a node under the conversation's daily label (/wake); the boxes of every pipe and of every
//! handed-out invitation read across the box's term (/fetch, days -8..+1), each row opened under its label's secret, placed,
//! answered «delivered», and confirmed to the node, which then removes it (/box-del).
//! Words of the wire (receipts, the read mark, the name, deletions, edits, reactions) change the feed, never stand as rows.
//! A letter too long for one envelope rides as a sealed blob the envelope names (LB:).

use crate::book::{birth_ms, mint_mid, Book, Chat, Msg, Pending};
use crate::card::Card;
use crate::profile::strip_crown;
use crate::vault::Vault;
use crate::wire::{self, b64, b64url, body_key, conv_w, domained, hex, rdv_conv_w, rdv_letter_secret, sha, sub_id, unb64, ENVELOPE};
use crate::{crypto, doors, http, media, meeting};
use serde_json::{json, Map, Value};

/// The words of the wire (Android Marks; iOS ContentView marks), byte for byte.
pub mod marks {
    pub const READ: &str = "\u{200B}\u{2063}"; // «read», + the birth millisecond of the newest letter covered
    pub const DELIVERED: &str = "\u{200B}\u{2064}"; // «delivered», + the letter's mid
    pub const NAME: &str = "\u{200B}\u{200B}NM:"; // + the display name
    pub const DELETE: &str = "\u{200B}\u{200B}DL:"; // + "mid:" + the letter's mid: taken away for both
    pub const EDIT: &str = "\u{200B}\u{200B}ED:"; // + {"sid": mid, "tx": words}
    pub const REACT: &str = "\u{200B}\u{200B}RC:"; // + {"sid": "mid:"+mid, "txt", "e", "op": add|del}
    pub const CARGO_GONE: &str = "\u{200B}\u{200B}CG:"; // + mid: the blob of that letter is gone
    pub const PIN: &str = "\u{200B}\u{200B}PN:"; // + {"sid": "mid:"+mid, "txt", "op": pin|unpin}
    pub const MEDIA: &str = "\u{200B}\u{200B}MD:"; // + the manifest of a picture, a film, a voice, a file
    pub const AVATAR: &str = "\u{200B}\u{200B}AV:"; // + base64 of a JPEG; empty: no face
    pub const ABOUT: &str = "\u{200B}\u{200B}AB:"; // + {"b": bio, "l": link, "at": seconds}
    pub const VOICE: &str = "\u{200B}\u{200B}VC:"; // an old voice letter, heard only
    pub const LONG: &str = "\u{2063}LB:"; // + {"r": bid, "k": key}: the words are a sealed blob
    pub const STICKER: &str = "\u{2063}\u{2063}"; // + an emoji: a person's letter drawn large
    pub const CONVDEL: &str = "\u{2063}mtconvdel:"; // the conversation erased for both, at the mid's birth
    pub const DRAFT: &str = "\u{2063}mtdraft:";
    pub const KEPT: &str = "\u{200B}\u{200B}DK:";
    pub const FLOW_ROW: &str = "\u{200B}\u{200B}MF:"; // the Money Flow began in this chat: this machine's own row, never on the wire // + the deletion's own payload: the correspondent kept the letter I deleted
    /// A word of the wire, not a row of the feed (a sticker and a picture are rows: see `is_row`).
    pub fn is_service(t: &str) -> bool {
        t.starts_with('\u{200B}') || t.starts_with('\u{2063}')
    }
    /// A person's letter: words, a sticker, a picture or a voice.
    pub fn is_row(t: &str) -> bool {
        !is_service(t) || t.starts_with(STICKER) || t.starts_with(MEDIA) || t.starts_with(VOICE)
    }
    /// What never rings (iOS isSilentLetter: control words and drafts; a picture, a voice and a sticker ring).
    pub fn is_silent(t: &str) -> bool {
        if t.starts_with(MEDIA) || t.starts_with(VOICE) {
            return false;
        }
        [READ, DELIVERED, CONVDEL, DRAFT].iter().any(|m| t.starts_with(m)) || t.starts_with("\u{200B}\u{200B}")
    }
}

/// Whose box a label of the pickup reads: an invitation's, a pipe's, or the pipe of this person's devices.
enum From {
    Invite(String),
    Pipe(String),
    Twin,
    /// the pipe of a slot this machine keeps for someone (iOS MTKeeping.listening)
    Keep(String),
}

/// ONE LANDING AT A TIME (iOS lands every road on one queue): the box's pickup, the lane's letter and a channel's letter each read
/// a chat and edit it, and two of them at once would lose one's edit -- a «read» told by one road under a row another road was
/// writing. A row's landing holds it; the network's waits never do.
static LANDING: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// A person's letter that just landed: the window may ring for it (iOS MontanaNotify.presentLetter).
pub struct News {
    pub chat: String,
    pub text: String,
    /// the same words naming nobody, for a person whose Show sender is off (iOS 2304 MontanaNotify.showsSender): a group's
    /// words without «who:», a room's call from «Correspondent»; None -- the words name nobody already
    pub anon: Option<String>,
}

/// What the postman needs of the person: the vault, the book, the twin reference, the author key, the name.
pub struct Desk<'a> {
    pub vault: &'a Vault,
    pub book: &'a Book,
    pub twin: String,
    pub author_key: Option<Vec<u8>>,
    pub my_name: String,
    /// the person's letters landed by this desk, for the banners
    pub news: std::sync::Mutex<Vec<News>>,
    /// the files of letters kept on this machine
    pub media: &'a media::Store,
    /// the faces of correspondents (by chat), and mine (empty: none)
    pub faces: &'a media::Store,
    pub self_face: Vec<u8>,
    /// my words about myself (bio, link), and whether my reading is told (iOS readReceiptsEnabled)
    pub about: (String, String),
    pub read_receipts: bool,
    /// the presence of my correspondents: a presence word that rode the box (a farewell «gone») lands there
    pub presence: &'a crate::presence::Presence,
    /// the history under the words (iOS MontanaArchive): every letter of the feed is written there too
    pub archive: Option<crate::history::Archive>,
}

/// A face's tag (Android annFace2): the first sixteen hex of its SHA-256 -- the empty face has one too.
pub fn face_tag(face: &[u8]) -> String {
    hex(&sha(&[face]))[..16].to_string()
}

/// The face laid beside a pipe for the other side to read at its birth (iOS layPipeFace / readPipeFace).
pub fn pipe_face_bid(secret: &[u8]) -> String {
    hex(&domained("mt-pipe-f", &[secret]))
}
pub fn pipe_face_key(secret: &[u8]) -> [u8; 32] {
    domained("mt-pipe-fk", &[secret])
}

const LONG_REFS: &str = "longRefs"; // mid -> the LB: word of my long letter (a resend reuses the blob)
const LONG_WAIT: &str = "longWait"; // mid -> the hours of a long letter of theirs whose blob did not come yet
const FIRST_BODY: usize = 1536;
const MEDIA_LETTERS: &str = "mediaLetters"; // mid -> the MD: letter that rides for my file (its pieces are up)
const MEDIA_GONE: &str = "mediaGone"; // mid -> true: a file of theirs no store holds any more
const MEDIA_WAIT: &str = "mediaWait"; // mid -> {next, tries}: a file of theirs asked again later
const ARCHIVE_HEADS: &str = "archiveHeads"; // ref -> the head last written into its archive folder

fn pad(mut b: Vec<u8>, to: usize) -> Option<Vec<u8>> {
    if b.len() > to {
        return None;
    }
    b.resize(to, 0);
    Some(b)
}

fn fields_of(parts: &[&str]) -> Vec<u8> {
    let mut b = Vec::new();
    for p in parts {
        b.extend_from_slice(p.as_bytes());
        b.push(0);
    }
    b
}

fn jmap(v: &Vault, name: &str) -> Map<String, Value> {
    match v.get(name).and_then(|b| serde_json::from_slice(&b).ok()) {
        Some(Value::Object(o)) => o,
        _ => Map::new(),
    }
}

fn first_chars(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

/// The mid inside a word that names a letter: "mid:" taken off, as both platforms write it either way.
fn bare(sid: &str) -> &str {
    sid.strip_prefix("mid:").unwrap_or(sid)
}

impl<'a> Desk<'a> {
    // ───────────────────────────── sending ─────────────────────────────

    /// THE LONG LETTER'S BLOB (iOS sealLongLetter; Android sealLong): mid‖0‖words sealed under a fresh key, laid on the node
    /// under the SHA-256 of the seal; the envelope carries {"r": bid, "k": key}. One blob per letter, reused by a resend.
    fn long_ref(&self, mid: &str, text: &str) -> Option<String> {
        if let Some(r) = jmap(self.vault, LONG_REFS).get(mid).and_then(|v| v.as_str()) {
            return Some(r.to_string());
        }
        let key = crypto::random(32)?;
        let sealed = crypto::seal(&key, &[mid.as_bytes(), &[0], text.as_bytes()].concat())?;
        let bid = hex(&sha(&[&sealed]));
        if !doors::put_new_blob(&bid, &sealed) {
            return None;
        }
        let word = format!("{}{}", marks::LONG, json!({ "r": bid, "k": b64(&key) }));
        let mut m = jmap(self.vault, LONG_REFS);
        m.insert(mid.to_string(), Value::String(word.clone()));
        while m.len() > 256 {
            let k = m.keys().next().cloned().unwrap();
            m.remove(&k);
        }
        self.vault.set(LONG_REFS, Value::Object(m).to_string().as_bytes());
        Some(word)
    }

    /// THE BODY OF ONE LETTER (iOS MTNodeWire.letterBody): mid‖0 words‖0 my name‖0 glyph‖0, the quote (its words, at most
    /// 200, and its mid) when it fits, the author's field over the words that ride; a body over one envelope rides as LB:.
    fn body(&self, secret: &[u8], mid: &str, text: &str, qt: &str, qm: &str, lp: &str) -> Option<Vec<u8>> {
        let name = self.my_name.trim();
        let mut words = text.to_string();
        let mut b = fields_of(&[mid, &words, name, ""]);
        if b.len() > ENVELOPE {
            words = self.long_ref(mid, text)?;
            b = fields_of(&[mid, &words, name, ""]);
        }
        let mut quoted = false;
        if !qt.is_empty() {
            let tail = fields_of(&[&first_chars(qt, 200), qm]);
            if b.len() + tail.len() <= ENVELOPE {
                b.extend_from_slice(&tail);
                quoted = true;
            }
        }
        // THE CARD STANDS SEVENTH (iOS sealLetterEnvelope): its words without the picture, after the quote's two fields -- empty
        // ones when the letter answers nothing; decoration: a card that does not fit rides not at all
        if let Some(card) = crate::linkcard::wire(lp) {
            let tail = if quoted { fields_of(&[&card]) } else { fields_of(&["", "", &card]) };
            if b.len() + tail.len() <= ENVELOPE {
                b.extend_from_slice(&tail);
            }
        }
        pad(wire::with_author(&b, self.author_key.as_deref(), secret, mid, &words), ENVELOPE)
    }

    /// ONE KNOCK (iOS MTNodeWire.knockLetter): the body sealed afresh at every door; the first door that boxes it ends the walk.
    fn knock(&self, secret: &[u8], mid: &str, text: &str, qt: &str, qm: &str, lp: &str) -> bool {
        let Some(plain) = self.body(secret, mid, text, qt, qm, lp) else { return false };
        // THE NEAR ROAD BESIDE THE BOX'S (iOS sendUnderTag): the same letter laid before the nodes under the pipe's tag when a path
        // stands; the receiving side drops the second copy by its mid
        crate::channels::lay(secret, mid, &plain);
        let cw = conv_w(secret, wire::day());
        for door in doors::write_order() {
            let Some(env) = wire::seal(&body_key(secret, wire::minute()), &plain) else { return false };
            let mut req = json!({ "conv": cw, "from_id": sub_id(&cw, &self.twin), "mid": mid, "env": b64(&env) });
            if marks::is_silent(text) && !crate::groups::rings(text) || crate::chess::is_step(text) && !crate::chess::rings(text) {
                req["silent"] = json!(true); // a game's step is the board's alone: a silent push (iOS MTChessLetter.rings)
            }
            if doors::post_at(&door, "/wake", &req, http::POST_DEADLINE_MS).0 == 200 {
                return true;
            }
        }
        false
    }

    /// THE FIRST-MEETING LETTER (iOS wakeRdv): [ct 1088][mid‖0 text‖0 name‖0 glyph‖0 conf‖0], padded to 1536 (words that do not
    /// fit ride as LB:), sealed under the invitation's letter key of this minute, boxed under the invitation's daily label.
    pub(crate) fn knock_first(&self, secret: &[u8], ct: &[u8], inv: &[u8], mid: &str, text: &str) -> bool {
        let conf = b64url(&domained("mt-first-conf", &[secret, ct])[..16]);
        let name = self.my_name.trim();
        let mut words = text.to_string();
        if ct.len() + fields_of(&[mid, &words, name, "", &conf]).len() > FIRST_BODY {
            let Some(w) = self.long_ref(mid, text) else { return false };
            words = w;
        }
        let body = [ct, &fields_of(&[mid, &words, name, "", &conf])].concat();
        let Some(plain) = pad(body, FIRST_BODY) else { return false };
        let letter_key = rdv_letter_secret(inv);
        let cw = rdv_conv_w(inv, wire::day());
        for door in doors::write_order() {
            let Some(env) = wire::seal(&body_key(&letter_key, wire::minute()), &plain) else { return false };
            let req = json!({ "conv": cw, "from_id": sub_id(&cw, &self.twin), "mid": mid, "env": b64(&env) });
            if doors::post_at(&door, "/wake", &req, http::POST_DEADLINE_MS).0 == 200 {
                return true;
            }
        }
        false
    }

    /// A word to a correspondence: by the invitation's box while the introduction is unanswered (a person's letters only --
    /// the words of the wire wait for the pipe, Android Meeting.knockFirst), under the pipe after.
    pub fn deliver(&self, r: &str, mid: &str, text: &str) -> bool {
        self.deliver_q(r, mid, text, "", "", "")
    }

    fn deliver_q(&self, r: &str, mid: &str, text: &str, qt: &str, qm: &str, lp: &str) -> bool {
        if crate::fabric::is_live_act(text) {
            crate::fabric::spoke(r); // a live act left for a correspondent (iOS MTFabric.spoke)
        }
        if let Some(gid) = r.strip_prefix("grp:") {
            let ok = self.group_deliver(gid, mid, text, qt, qm); // a group's chat: the words go as group words over the pipes
            if ok && !lp.is_empty() {
                self.group_card(gid, mid, lp); // the letter's card rides after it as the group's own word (iOS carryCard)
            }
            return ok;
        }
        let Some(secret) = self.book.secret(r) else { return false };
        // a blocked person hears no word of mine but the farewell: the face taken back and «gone» (iOS silenced)
        if self.book.chat(r).is_some_and(|c| c.blocked) && text != marks::AVATAR && !text.starts_with(&format!("{}0B", crate::presence::APP)) {
            return true;
        }
        match meeting::first(self.vault, r) {
            Some(_) if !marks::is_row(text) => false,
            Some((ct, inv)) => self.knock_first(&secret, &ct, &inv, mid, text),
            None => self.knock(&secret, mid, text, qt, qm, lp),
        }
    }

    /// A word of the wire that must arrive (iOS: the durable queue): kept first, said now, let go once a node took it; kept
    /// words are said again by the next walks for a day -- a window closed mid-way loses none.
    fn word(&self, r: &str, mid: &str, text: &str) {
        if crate::book::is_saved(r) {
            return; // the room without a wire says nothing to anyone: its edits, answers and deletions stay here (iOS isLocalRoom)
        }
        self.mirror_sent(r, mid, text, "", "", "");
        self.word_kept(r, mid, text);
    }

    /// The same durable word without the twin's mirror (a group's copy rides the mirror as the copy it is): kept first, said
    /// now, let go once a node took it, said again by the walks for a day. True when a node took it now.
    pub(crate) fn word_kept(&self, r: &str, mid: &str, text: &str) -> bool {
        if crate::book::is_saved(r) {
            return true;
        }
        let p = Pending { mid: mid.to_string(), text: text.to_string(), at: wire::now_ms() };
        self.book.edit(r, |c| c.pending.push(p));
        let ok = self.deliver(r, mid, text);
        if ok {
            self.book.edit(r, |c| c.pending.retain(|x| x.mid != mid));
        }
        ok
    }

    /// A person's letter: a row «sending» at once (the window draws it before the network is asked); its mid.
    pub fn draft(&self, r: &str, text: &str, qt: &str, qm: &str) -> String {
        self.draft_as(r, &mint_mid(), text, qt, qm)
    }

    /// A letter into the archive (iOS MontanaArchive.archive): the head of its folder first -- the secret and the name, once
    /// and again when the name changes -- then the letter, a file in the archive's own form.
    pub fn archive_row(&self, r: &str, mine: bool, at_ms: i64, mid: &str, text: &str) {
        let Some(a) = &self.archive else { return };
        let Some(c) = self.book.chat(r) else { return };
        let mut heads = jmap(self.vault, ARCHIVE_HEADS);
        let held = heads.get(r).and_then(|v| v.as_str()).unwrap_or("").to_string();
        let now = (wire::now_ms() / 1000) as u64;
        let saved = crate::book::is_saved(r);
        if saved {
            // SAVED MESSAGES' FOLDER SAYS ITS OWN KEY ONCE (iOS writeHeadIn, the form «a»): no secret, no name
            if held.is_empty() {
                a.append(r, 2, now, format!("a:{r}").as_bytes());
                heads.insert(r.to_string(), Value::String("a".into()));
                self.vault.set(ARCHIVE_HEADS, Value::Object(heads.clone()).to_string().as_bytes());
            }
        } else if held.is_empty() {
            if let Some(secret) = self.book.secret(r) {
                a.append(r, 2, now, format!("s:{}", b64(&secret)).as_bytes());
            }
        }
        let name = c.name.trim().to_string();
        if saved {
            // no name rides its folder
        } else if !name.is_empty() && held != format!("n:{name}") {
            a.append(r, 2, now, format!("n:{name}").as_bytes());
            heads.insert(r.to_string(), Value::String(format!("n:{name}")));
            self.vault.set(ARCHIVE_HEADS, Value::Object(heads).to_string().as_bytes());
        } else if held.is_empty() {
            heads.insert(r.to_string(), Value::String("s".into()));
            self.vault.set(ARCHIVE_HEADS, Value::Object(heads).to_string().as_bytes());
        }
        let content = if text.starts_with(media::MARK) { crate::history::archive_media(mid, text) } else { text.to_string() };
        a.append(r, if mine { 0 } else { 1 }, (at_ms / 1000).max(0) as u64, content.as_bytes());
        self.twin_soon("hist", 30_000); // the other devices get the block within half a minute (iOS twinSoon)
    }

    fn draft_as(&self, r: &str, mid: &str, text: &str, qt: &str, qm: &str) -> String {
        let mid = mid.to_string();
        let at = birth_ms(&mid).unwrap_or_else(wire::now_ms);
        let saved = crate::book::is_saved(r);
        if saved {
            self.book.edit(r, |_| {});   // the room is born with its first letter (iOS seedIfNeeded)
        }
        // a file of Saved Messages is archived at its birth, as iOS archives every file (it rides nowhere else)
        if !text.starts_with(media::MARK) || saved {
            self.archive_row(r, true, at, &mid, text);
        }
        // a letter of Saved Messages stands «sent» at its birth: there is no road to wait for (iOS isLocalRoom: .sent)
        let row = Msg { mid: mid.clone(), text: text.to_string(), mine: true, at, qt: first_chars(qt, 200), qm: qm.to_string(),
                        state: if saved { 1 } else { 0 }, ..Default::default() };
        self.book.edit(r, |c| {
            c.msgs.push(row);
            c.hidden = false;
        });
        self.mint_letter(r, &mid, text, at);
        mid
    }

    /// EVERY LETTER OF A PAIR'S CHAT MINTS ITS COIN (iOS MTCoinSend.mintLetter, the author's word 11.10.2026): a letter of mine or of
    /// my correspondent mints the second's one coin once by its wire name on this machine -- the other side's mints its own; a coin
    /// letter, a transfer's telling letter, a game's step and a group's word mint nothing.
    fn mint_letter(&self, r: &str, mid: &str, text: &str, at: i64) {
        // THE BOOK IS HEARD BEFORE A LETTER MINTS (iOS MTChatMint.credit, the author's words 09.10.2026): until the seed's vault
        // answered, the letter waits and is paid by `mint_waiting` under the book that holds it
        if !Self::mints(r, text) || !crate::coinvault::heard() {
            return;
        }
        crate::coins::earn(self.vault, &[(format!("mid:{mid}"), at)], None);
    }
    fn mints(r: &str, text: &str) -> bool {
        !(crate::groups::is_group(r) || crate::book::is_saved(r) || !marks::is_row(text) || crate::chess::is_step(text) || crate::coins::letter_of(text).is_some() || crate::coins::is_transfer(text))
    }

    /// THE LETTERS THAT LANDED BEFORE THE BOOK WAS HEARD MINT NOW (iOS MTCoinVault.gather -> MTChatMint.credit): every pair's letters
    /// born since the coin came on are walked once the vault answered, each paid once by its name; the coins minted.
    pub fn mint_waiting(&self) -> i64 {
        let mut got = 0;
        for c in self.book.all() {
            let names: Vec<(String, i64)> = c.msgs.iter().filter(|m| Self::mints(&c.reference, &m.text)).map(|m| (format!("mid:{}", m.mid), m.at)).collect();
            if !names.is_empty() {
                got += crate::coins::earn(self.vault, &names, None);
            }
        }
        got
    }

    /// A file of mine as a letter: the row stands at once with the file kept here; the pieces go up when the letter goes.
    pub fn draft_media(&self, r: &str, bytes: &[u8], manifest: Value, qt: &str, qm: &str) -> Option<String> {
        let mid = mint_mid();
        if !self.media.put(&mid, bytes) {
            return None;
        }
        let mut m = manifest;
        m["sz"] = json!(bytes.len());
        m["local"] = json!(true);
        Some(self.draft_as(r, &mid, &format!("{}{}", media::MARK, m), qt, qm))
    }

    /// A BIG FILE AS A LETTER (iOS sendMedia with MediaSource.file): its pieces already kept under the letter's name, handed by
    /// the window a stretch at a time; the letter stands once they are whole.
    pub fn draft_big(&self, r: &str, mid: &str, size: u64, manifest: Value, qt: &str, qm: &str) -> Option<String> {
        if !self.media.close_big(mid, size) {
            return None;
        }
        let mut m = manifest;
        m["sz"] = json!(size);
        m["local"] = json!(true);
        Some(self.draft_as(r, mid, &format!("{}{}", media::MARK, m), qt, qm))
    }

    /// The letter that rides for a row: for a file of mine, its pieces laid on the node first (iOS: the letter is queued only
    /// after the chunks are up), the manifest written into the row without the «local» mark.
    fn riding(&self, r: &str, mid: &str, text: &str) -> Option<String> {
        if !text.starts_with(media::MARK) {
            return Some(text.to_string());
        }
        if let Some(l) = jmap(self.vault, MEDIA_LETTERS).get(mid).and_then(|v| v.as_str()) {
            return Some(l.to_string());
        }
        let mut m: Value = serde_json::from_str(&text[media::MARK.len()..]).ok()?;
        if m["local"].as_bool() != Some(true) {
            return Some(text.to_string());
        }
        let _hand = media::in_hand(mid)?;
        // A FILM IS MADE LIGHT BEFORE ITS PIECES GO (iOS compressResumable): once a letter; its ring 0…30 % the writing, 30…100 %
        // the pieces -- anything else 0…100 % the pieces (a round note is born light, as iOS's _mtc)
        let film = m["k"].as_str() == Some("vid") && m["r"].as_bool() != Some(true);
        if film && m["sq"].as_bool() != Some(true) {
            self.squeeze(r, mid, &mut m);
        }
        if media::stopped(mid) {
            media::tell(mid, None);
            return None;
        }
        let held;
        let src = match self.media.big(mid) {
            Some(size) => media::Source::Parts(self.media, mid, size),
            None => {
                held = self.media.get(mid)?;
                media::Source::Bytes(&held)
            }
        };
        let key = media::letter_key(self.vault, mid)?;
        let base: f64 = if film { 0.3 } else { 0.0 };
        media::tell(mid, Some((base.max(0.01), "")));
        let chunks = media::upload_told(&src, &key, Some((mid, base)));
        media::tell(mid, None);
        media::let_go(mid);
        let chunks = chunks?;
        m.as_object_mut()?.remove("local");
        m.as_object_mut()?.remove("sq");
        m["bk"] = json!(b64(&key));
        m["sz"] = json!(src.len());
        m["chunks"] = json!(chunks);
        let letter = media::manifest_letter(&m)?;
        let mut l = jmap(self.vault, MEDIA_LETTERS);
        l.insert(mid.to_string(), Value::String(letter.clone()));
        self.vault.set(MEDIA_LETTERS, Value::Object(l).to_string().as_bytes());
        let row = format!("{}{}", media::MARK, m);
        self.archive_row(r, true, birth_ms(mid).unwrap_or_else(wire::now_ms), mid, &row);
        self.mirror_sent(r, mid, &letter, "", "", ""); // the media letter, to the other devices (iOS promotePiece)
        self.book.edit(r, |c| { if let Some(x) = c.msgs.iter_mut().find(|x| x.mid == mid) { x.text = row; } });
        Some(letter)
    }

    /// A FILM MADE LIGHT (iOS sendMediaOverE2E -> MontanaVideo.compressResumable): the kept film written out, written again within
    /// the preset's box (videoconv), and taken back under the letter's own name -- the row then says mp4 and the new size; a film
    /// that stays as it was goes as it was. The row keeps the mark «sq» (this computer's own, never on the wire): the walk that
    /// takes the letter again writes nothing again (iOS MontanaVideoMark).
    fn squeeze(&self, r: &str, mid: &str, m: &mut Value) {
        use crate::videoconv::{squeeze, Step};
        let ext = m["e"].as_str().unwrap_or("mp4").to_lowercase();
        let name = &crate::wire::hex(&crate::wire::sha(&[mid.as_bytes()]))[..16];
        let src = std::env::temp_dir().join(format!("montana-film-{name}.{ext}"));
        if self.media.write_to(mid, &src) {
            let stop = media::stop_flag(mid);
            let out = squeeze(&src, &ext, &|s| match s {
                Step::Waiting => media::tell(mid, Some((0.01, "queue"))),
                Step::Began => media::tell(mid, Some((0.01, "squeeze"))),
                Step::Share(x) => media::tell(mid, Some((0.01 + x * 0.29, &format!("squeeze {}", (x * 100.0) as u32)))),
            }, &stop);
            if let Some(out) = out {
                if let Some(size) = self.media.take_file(mid, &out) {
                    m["e"] = json!("mp4");
                    m["sz"] = json!(size);
                }
                let _ = std::fs::remove_file(&out);
            }
            let _ = std::fs::remove_file(&src);
        }
        m["sq"] = json!(true);
        let row = format!("{}{}", media::MARK, m);
        self.book.edit(r, |c| { if let Some(x) = c.msgs.iter_mut().find(|x| x.mid == mid) { x.text = row.clone(); } });
    }

    /// The drafted letter on its way; «sent» once a node boxed it, else it waits for the next walk.
    pub fn post(&self, r: &str, mid: &str) -> bool {
        if crate::book::is_saved(r) {
            return true; // Saved Messages: born «sent» and archived, nothing to carry
        }
        self.announce(r);
        let Some(m) = self.book.chat(r).and_then(|c| c.msgs.into_iter().find(|m| m.mid == mid)) else { return false };
        let Some(text) = self.riding(r, mid, &m.text) else { return false };
        if !text.starts_with(media::MARK) {
            self.mirror_sent(r, mid, &text, &m.qt, &m.qm, &m.lp); // what the person sends rides to the other devices (iOS enqueue)
        }
        let ok = self.deliver_q(r, mid, &text, &m.qt, &m.qm, &m.lp);
        if ok {
            self.book.edit(r, |c| { if let Some(m) = c.msgs.iter_mut().find(|m| m.mid == mid) { m.advance(1); } });
        }
        ok
    }

    #[cfg(test)]
    pub fn send(&self, r: &str, text: &str) -> String {
        let mid = self.draft(r, text, "", "");
        self.post(r, &mid);
        mid
    }

    /// The letters of mine no node took yet go again, and the words of the wire waiting (iOS outbox walk); my name where
    /// it is not said yet.
    pub fn flush(&self) -> bool {
        let mut moved = false;
        let now = wire::now_ms();
        for c in self.book.all() {
            for m in c.msgs.iter().filter(|m| m.mine && m.state == 0) {
                let Some(text) = self.riding(&c.reference, &m.mid, &m.text) else { continue };
                if self.deliver_q(&c.reference, &m.mid, &text, &m.qt, &m.qm, &m.lp) {
                    self.book.edit(&c.reference, |c| { if let Some(x) = c.msgs.iter_mut().find(|x| x.mid == m.mid) { x.advance(1); } });
                    moved = true;
                }
            }
            if !c.pending.is_empty() {
                let mut left = vec![];
                for p in &c.pending {
                    if now - p.at < 86_400_000 && !self.deliver(&c.reference, &p.mid, &p.text) {
                        left.push(p.clone());
                    }
                }
                self.book.edit(&c.reference, |c| c.pending = left);
            }
            if !c.hidden && !crate::groups::is_group(&c.reference) && !crate::book::is_saved(&c.reference) {
                self.announce(&c.reference);
                if !c.msgs.is_empty() {
                    self.announce_face(&c.reference);
                    self.announce_about(&c.reference);
                }
            }
        }
        moved
    }

    /// My own name goes to a correspondent (Android announce): said again only when it changed, and never twice within the hour
    /// while the first is on its way; the receipt of that very letter is what records it as said.
    pub fn announce(&self, r: &str) {
        let name = strip_crown(self.my_name.trim());
        let Some(c) = self.book.chat(r) else { return };
        if name.is_empty() || c.announced == name || meeting::first(self.vault, r).is_some() {
            return;
        }
        let f: Vec<&str> = c.name_flight.split('\n').collect();
        if f.len() == 3 && f[0] == name && wire::now_ms() - f[2].parse::<i64>().unwrap_or(0) < 3_600_000 {
            return;
        }
        let mid = mint_mid();
        self.book.edit(r, |c| c.name_flight = format!("{name}\n{mid}\n{}", wire::now_ms()));
        self.deliver(r, &mid, &format!("{}{name}", marks::NAME));
    }

    /// My face goes to a correspondent (Android announce, the face): said when its tag differs from the one their receipt
    /// confirmed, never twice within the hour while on its way; an empty word takes a face back. It is long: it rides as LB:.
    pub fn announce_face(&self, r: &str) {
        let Some(c) = self.book.chat(r) else { return };
        let tag = face_tag(&self.self_face);
        if c.face_said == tag || meeting::first(self.vault, r).is_some() || (self.self_face.is_empty() && c.face_said.is_empty()) {
            return;
        }
        let f: Vec<&str> = c.face_flight.split('\n').collect();
        if f.len() == 3 && f[0] == tag && wire::now_ms() - f[2].parse::<i64>().unwrap_or(0) < 3_600_000 {
            return;
        }
        let mid = mint_mid();
        self.book.edit(r, |c| c.face_flight = format!("{tag}\n{mid}\n{}", wire::now_ms()));
        let word = if self.self_face.is_empty() { marks::AVATAR.to_string() } else { format!("{}{}", marks::AVATAR, b64(&self.self_face)) };
        self.deliver(r, &mid, &word);
    }

    /// A WORD OF THE WALL HEARD (iOS MTBoard.handle): kept, and what it asks for said back on the same pipe.
    fn wall_word(&self, r: &str, text: &str) {
        let Some(w) = crate::board::parse(text) else { return };
        let names = |c: &str| self.book.chat(c).map(|c| if c.alias.trim().is_empty() { c.name } else { c.alias }).unwrap_or_default();
        for (to, back) in crate::board::apply(self.vault, &w, r, &names) {
            self.wall_say(&to, &back);
        }
    }

    /// A word of the wall to a correspondent; a page carried is recorded as theirs once the network took it (iOS delivered).
    pub fn wall_say(&self, r: &str, w: &crate::board::Word) -> bool {
        if crate::groups::is_group(r) || self.book.secret(r).is_none() {
            return false;
        }
        let ok = self.deliver(r, &mint_mid(), &crate::board::letter(w));
        if w.t == "page" {
            match (ok, &w.v) {
                (true, Some(v)) => crate::board::page_sent(self.vault, r, v),
                _ => crate::board::push_again(self.vault),
            }
        }
        ok
    }

    /// My words about myself (iOS E2E.sendAboutIfNeeded): {"b","l","at"} when they changed since the receipt that recorded
    /// them, never twice within the hour while on their way; nothing while both are empty and were never said.
    pub fn announce_about(&self, r: &str) {
        self.announce_about_asking(r, false);
    }
    /// The same word asking theirs back (iOS sendAboutIfNeeded askKey): my send found no key of theirs, so «q» rides it and their
    /// computer tells its key again; the word goes whatever was receipted.
    pub fn announce_about_asking(&self, r: &str, ask_key: bool) {
        let Some(c) = self.book.chat(r) else { return };
        let (bio, link) = (&self.about.0, &self.about.1);
        let tag = if bio.is_empty() && link.is_empty() { "0".to_string() } else { face_tag(format!("{bio}\n{link}").as_bytes()) };
        let key = crate::wallet::MY_FROM.lock().unwrap().clone();
        let key_due = ask_key || key.as_ref().is_some_and(|k| !crate::wallet::told_key(self.vault, r, k));
        if meeting::first(self.vault, r).is_some() || (!key_due && (c.about_said == tag || (tag == "0" && c.about_said.is_empty()))) {
            return;
        }
        let f: Vec<&str> = c.about_flight.split('\n').collect();
        if !ask_key && f.len() == 3 && f[0] == tag && wire::now_ms() - f[2].parse::<i64>().unwrap_or(0) < 3_600_000 {
            return;
        }
        let mid = mint_mid();
        self.book.edit(r, |c| c.about_flight = format!("{tag}\n{mid}\n{}", wire::now_ms()));
        let mut w = json!({ "b": bio, "l": link, "at": wire::now_ms() as f64 / 1000.0 });
        if let Some(k) = &key {
            w["k"] = json!(k); // my coin key's tag: a SEND of version 3 commits to it (COIN-TX-V3 section 1)
        }
        if ask_key {
            w["q"] = json!(1); // my send found no key of theirs: their computer tells it again (iOS ChatStore, the about word)
        }
        if self.deliver(r, &mid, &format!("{}{}", marks::ABOUT, w)) {
            if let Some(k) = &key {
                crate::wallet::note_told_key(self.vault, r, k);
            }
        }
    }

    /// THEIR FACE WORN (iOS ChatStore.saveAvatar): kept for the screens, and sealed beside their letters in the archive under the
    /// seed's media key (15.10.4) -- a restore by the same words wears it again. A group's face rides no archive.
    pub fn wear_face(&self, r: &str, face: &[u8]) -> bool {
        if !self.faces.put(r, face) {
            return false;
        }
        if let Some(a) = self.archive.as_ref().filter(|_| !crate::groups::is_group(r)) {
            a.put_media(r, crate::history::FACE_BLOB, face);
        }
        true
    }

    /// Their face beside a pipe just born (iOS readPipeFace): asked at once and twice more across eight seconds.
    pub fn read_pipe_face(&self, r: &str, secret: &[u8]) {
        for pause in [0u64, 2, 6] {
            std::thread::sleep(std::time::Duration::from_secs(pause));
            let Some(sealed) = doors::get_blob(&pipe_face_bid(secret)) else { continue };
            if let Some(face) = crypto::open(&pipe_face_key(secret), &sealed).filter(|f| !f.is_empty() && f.len() <= 262_144) {
                if self.book.chat(r).is_some_and(|c| c.face_at == 0) && self.wear_face(r, &face) {
                    self.book.edit(r, |c| c.face_at = 1);
                }
            }
            return;
        }
    }

    /// «delivered» for a letter of theirs: one name per letter, so a repeated receipt is one word (Android receipt «rcpt-»).
    fn receipt(&self, r: &str, mid: &str) {
        self.deliver(r, &format!("rcpt-{mid}"), &format!("{}{mid}", marks::DELIVERED));
    }

    /// I read their letters: the read mark goes with the birth of the newest one covered (iOS markRead).
    pub fn mark_read(&self, r: &str) {
        let Some(c) = self.book.chat(r) else { return };
        let newest = c.msgs.iter().filter(|m| !m.mine).filter_map(|m| birth_ms(&m.mid)).max();
        // THE OTHER DEVICES READ IT TOO (iOS markRead, the twin mirror): what was unread here is read there up to the same letter
        if c.unread > 0 || c.marked {
            if let Some(ms) = c.msgs.iter().filter(|m| !m.mine).map(|m| birth_ms(&m.mid).unwrap_or(m.at)).max().filter(|ms| *ms > 0) {
                self.mirror_note(crate::twin::Word { c: r.into(), m: crate::book::mint_mid(), x: format!("{}{ms}", crate::twin::READ_MARK), o: Some(1), ..Default::default() });
            }
        }
        self.book.edit(r, |c| {
            c.unread = 0;
            c.marked = false;
        });
        if crate::groups::is_group(r) {
            self.channel_seen(r); // a channel's posts shown: their names to its owner, for the eye under each
        }
        if !self.read_receipts || c.blocked {
            return; // the person keeps their reading to themselves, or it is a blocked one (iOS read_skip): nothing is said
        }
        if let Some(ms) = newest {
            self.deliver(r, &mint_mid(), &format!("{}{ms}", marks::READ));
        }
    }

    /// FORWARD (iOS Forward, Android LetterDeeds 16-18): the words or the file go again into another correspondence, marked
    /// «↪︎ Forwarded message» in the quote's place (a file also «fw»); the new letter is my own, with a name of its own.
    pub fn forward(&self, from: &str, mid: &str, to: &str) -> Option<String> {
        let m = self.book.chat(from)?.msgs.into_iter().find(|m| m.mid == mid)?;
        let mark = "\u{21AA}\u{FE0E} Forwarded message";
        if let Some(j) = m.text.strip_prefix(media::MARK) {
            let o: Value = serde_json::from_str(j).ok()?;
            let mut f = json!({ "k": o["k"].as_str().unwrap_or("doc"), "e": o["e"].as_str().unwrap_or("bin"), "fw": true });
            for k in ["n", "cap", "th", "du", "r", "wv"] {
                if !o[k].is_null() {
                    f[k] = o[k].clone();
                }
            }
            let new = match self.media.big(mid) {
                Some(size) => {
                    let new = mint_mid();
                    if !self.media.copy_big(mid, &new) {
                        return None;
                    }
                    self.draft_big(to, &new, size, f, mark, "")?
                }
                None => self.draft_media(to, &self.media.get(mid)?, f, mark, "")?,
            };
            self.post(to, &new);
            return Some(new);
        }
        if !marks::is_row(&m.text) {
            return None;
        }
        let new = self.draft(to, &m.text, mark, "");
        self.post(to, &new);
        Some(new)
    }

    /// PIN (iOS LetterDeeds pin): the letter stands over the chat; «for both» says PN: and theirs stands too, «for me» says
    /// nothing; unpinning always says it.
    pub fn pin(&self, r: &str, mid: &str, on: bool, both: bool) {
        let Some(m) = self.book.chat(r).and_then(|c| c.msgs.into_iter().find(|m| m.mid == mid)) else { return };
        self.book.edit(r, |c| {
            c.pins.retain(|p| p != mid);
            if on {
                c.pins.push(mid.to_string());
            }
        });
        if !on || both {
            let w = json!({ "sid": format!("mid:{mid}"), "txt": m.text, "op": if on { "pin" } else { "unpin" } });
            self.word(r, &mint_mid(), &format!("{}{}", marks::PIN, w));
        }
    }

    /// DELETE (iOS MontanaConversation delete): the letters leave my feed and their names are buried; «for everyone» says
    /// DL: for each, and the other side takes them away too. In a conversation of two any letter may go, mine or theirs.
    pub fn delete(&self, r: &str, mids: &[String], everyone: bool) {
        self.book.edit(r, |c| {
            for m in mids {
                c.bury(m);
            }
        });
        if everyone {
            for m in mids {
                self.word(r, &mint_mid(), &format!("{}mid:{m}", marks::DELETE));
            }
        }
    }

    /// EDIT (iOS ChatStore.editMessage): my own letter of words takes new words here and there; nothing goes if nothing changed.
    pub fn edit_letter(&self, r: &str, mid: &str, words: &str) -> bool {
        let Some(old) = self.book.chat(r).and_then(|c| c.msgs.into_iter().find(|m| m.mid == mid)) else { return false };
        if !old.mine || !marks::is_row(&old.text) || marks::is_service(&old.text) || old.text == words || words.trim().is_empty() {
            return false;
        }
        self.book.edit(r, |c| {
            if let Some(m) = c.msgs.iter_mut().find(|m| m.mid == mid) {
                m.text = words.to_string();
                m.edited = true;
            }
        });
        if old.state >= 1 {
            self.word(r, &mint_mid(), &format!("{}{}", marks::EDIT, json!({ "sid": mid, "tx": words })));
        }
        true
    }

    /// COINS GIVEN ON A CORRESPONDENT'S LETTER (iOS MTCoinSend.react / give, the author's word 03.10 13:40): the book pays on the
    /// letter's name -- refused on a short balance -- and the reaction word carries the coins (op «coin», c, r); an older build reads
    /// an unknown op as nothing. `refr` names the payment: a fresh one for a hand's gift, «auto:» and the letter's name for an
    /// auto-reaction, so a letter brought twice pays once.
    pub fn give(&self, r: &str, mid: &str, coins: i64, refr: &str, hands: Option<&crate::cointx::Hands>) -> bool {
        if coins <= 0 || crate::groups::is_group(r) || self.book.chat(r).is_some_and(|c| c.blocked) {
            return false;
        }
        let Some(m) = self.book.chat(r).and_then(|c| c.msgs.into_iter().find(|m| m.mid == mid)).filter(|m| !m.mine) else { return false };
        let sid = format!("mid:{mid}");
        // A PAID REACTION IS A SEND OF THE CHAIN (iOS 2304 MTCoinSend.give, the author's words 23.10.2026 03:27 and 03:37 MSK): the
        // pair's SEND under the letter's name; the word names it and carries no coins of its own -- the reader's computer takes them
        // from the chain alone. A SEND still waiting for its node's word has left the book and says no name: the reader's scan
        // credits it.
        if let (Some(h), Some(secret)) = (hands, self.book.secret(r)) {
            return match crate::wallet::send3(self.vault, h, r, &secret, coins, Some(&sid)) {
                crate::wallet::Sent::Taken(id) => {
                    let w = json!({ "sid": sid, "txt": m.text, "e": "🪙", "op": "coin3", "c": coins, "tx": id });
                    self.word(r, &mint_mid(), &format!("{}{}", marks::REACT, w));
                    crate::trace_line(&format!("coin_reaction v3 coins={coins}"));
                    true
                }
                crate::wallet::Sent::Pending => true,
                _ => false,
            };
        }
        // no coin key in hand (an auto-reaction at a letter's landing): the book's own road, the word carrying the coins
        if !crate::coins::moved(self.vault, "spend", coins, refr, Some(r), Some(&sid)) {
            return false;
        }
        let w = json!({ "sid": sid, "txt": m.text, "e": "🪙", "op": "coin", "c": coins, "r": refr });
        self.word(r, &mint_mid(), &format!("{}{}", marks::REACT, w));
        crate::trace_line(&format!("coin_reaction given coins={coins}"));
        true
    }

    /// REACT (iOS MontanaConversation.react): one answer per person -- the same one again takes it back, another replaces it.
    pub fn react(&self, r: &str, mid: &str, emoji: &str) {
        let Some(m) = self.book.chat(r).and_then(|c| c.msgs.into_iter().find(|m| m.mid == mid)) else { return };
        let say = |e: &str, op: &str| {
            let w = json!({ "sid": format!("mid:{mid}"), "txt": m.text, "e": e, "op": op });
            self.word(r, &mint_mid(), &format!("{}{}", marks::REACT, w));
        };
        let next = if m.my_react == emoji { String::new() } else { emoji.to_string() };
        self.book.edit(r, |c| { if let Some(x) = c.msgs.iter_mut().find(|x| x.mid == mid) { x.my_react = next.clone(); } });
        if !m.my_react.is_empty() {
            say(&m.my_react, "del");
        }
        if !next.is_empty() {
            say(&next, "add");
        }
    }

    /// BLOCK (iOS E2E.announceBlocked): nothing of theirs lands from now; they are told only that my face is taken back and
    /// that I am gone (AP:0B), both durable words.
    pub fn block(&self, r: &str) {
        self.book.edit(r, |c| {
            c.blocked = true;
            c.pinned_at = 0;
        });
        self.word(r, &mint_mid(), marks::AVATAR);
        self.word(r, &mint_mid(), &format!("{}0B{}", crate::presence::APP, self.presence.said_tail()));
    }

    /// UNBLOCK (iOS E2E.unblocked): my name, face and words about myself are said again with the next walk, and I am here.
    pub fn unblock(&self, r: &str) {
        self.book.edit(r, |c| {
            c.blocked = false;
            c.announced.clear();
            c.name_flight.clear();
            c.face_said.clear();
            c.face_flight.clear();
            c.about_said.clear();
            c.about_flight.clear();
        });
        self.word(r, &mint_mid(), &format!("{}1{}", crate::presence::APP, self.presence.said_tail()));
    }

    /// ERASE THE CONVERSATION (iOS ChatStore.deleteChat): «for me» empties the feed here; «for both» also says the funeral word,
    /// its mid's birth the moment, and the pipe is forgotten once the other side answers it.
    pub fn erase(&self, r: &str, both: bool) {
        let fm = mint_mid();
        let born = birth_ms(&fm).unwrap_or_else(wire::now_ms);
        self.book.edit(r, |c| {
            c.msgs.clear();
            c.unread = 0;
            c.hidden = true;
            c.held_edits.clear();
            if both {
                c.funeral = born;
                c.funeral_mid = fm.clone();
            }
        });
        if both {
            self.word(r, &fm, marks::CONVDEL);
        }
    }

    // ───────────────────────────── receiving ─────────────────────────────

    /// THE FILES OF THEIR LETTERS (iOS receive): a named manifest unfolded into the row, the pieces fetched, checked and kept;
    /// «delivered» only once the file is whole; a file gone from every store is said once (CG:) and stays «not received».
    /// One file per call; `want` names a file the person asked for whatever its size. True when something changed. A file of
    /// mine another device of the person sent (the twin mirror) comes the same way, answered to nobody.
    pub fn fetch_media(&self, want: Option<&str>, auto_limit: u64) -> bool {
        let now = wire::now_ms() / 1000;
        let gone = jmap(self.vault, MEDIA_GONE);
        let mut wait = jmap(self.vault, MEDIA_WAIT);
        let riding = |t: &str| t.contains("\"mref\"") || t.contains("\"chunks\"");
        for c in self.book.all() {
            for m in c.msgs.iter().filter(|m| m.text.starts_with(media::MARK) && (!m.mine || riding(&m.text))) {
                if self.media.has(&m.mid) {
                    continue;
                }
                let wanted = want == Some(m.mid.as_str());
                // THE FILE THE PERSON'S OWN NODE KEEPS comes back from it at a tap (iOS MTHomeKeep.bring, force) -- before any store
                // of the network, and never «gone» while the node's book names it
                if wanted && crate::homeshelf::bring_letter(self.vault, self.media, &m.mid, &m.text) {
                    return true;
                }
                if gone.contains_key(&m.mid) {
                    continue;
                }
                if !wanted && wait.get(&m.mid).and_then(|w| w["next"].as_i64()).is_some_and(|n| n > now) {
                    continue;
                }
                let manifest = match media::manifest_of(&m.text) {
                    Ok(v) => v,
                    Err(g) => return self.media_failed(&c.reference, &m.mid, g && !m.mine, &mut wait),
                };
                if m.text.contains("\"mref\"") {
                    let row = format!("{}{}", media::MARK, manifest);
                    self.book.edit(&c.reference, |c| { if let Some(x) = c.msgs.iter_mut().find(|x| x.mid == m.mid) { x.text = row; } });
                }
                if !wanted && manifest["sz"].as_u64().unwrap_or(0) > auto_limit {
                    continue; // a big file waits for the person's tap
                }
                // a big file comes piece by piece into the store, never whole in memory (iOS downloadToFile)
                let got = if media::is_big(&manifest) {
                    media::download_into(&manifest, self.media, &m.mid).map(|_| true)
                } else {
                    media::download(&manifest).map(|bytes| self.media.put(&m.mid, &bytes))
                };
                return match got {
                    Ok(true) => {
                        wait.remove(&m.mid);
                        self.vault.set(MEDIA_WAIT, Value::Object(wait).to_string().as_bytes());
                        if !m.mine {
                            self.receipt(&c.reference, &m.mid);
                        }
                        true
                    }
                    Ok(_) => false,
                    Err(g) if m.mine && g => {
                        // my own file, gone from every store: kept as gone here, said to nobody
                        let mut gm = jmap(self.vault, MEDIA_GONE);
                        gm.insert(m.mid.clone(), json!(true));
                        self.vault.set(MEDIA_GONE, Value::Object(gm).to_string().as_bytes());
                        true
                    }
                    Err(g) => self.media_failed(&c.reference, &m.mid, g, &mut wait),
                };
            }
        }
        false
    }

    fn media_failed(&self, r: &str, mid: &str, gone: bool, wait: &mut Map<String, Value>) -> bool {
        if gone {
            let mut g = jmap(self.vault, MEDIA_GONE);
            g.insert(mid.to_string(), json!(true));
            self.vault.set(MEDIA_GONE, Value::Object(g).to_string().as_bytes());
            self.deliver(r, &mint_mid(), &format!("{}{mid}", marks::CARGO_GONE));
            return true;
        }
        let tries = wait.get(mid).and_then(|w| w["tries"].as_i64()).unwrap_or(0);
        wait.insert(mid.to_string(), json!({ "next": wire::now_ms() / 1000 + (15i64 << tries.min(8)).min(3600), "tries": tries + 1 }));
        self.vault.set(MEDIA_WAIT, Value::Object(wait.clone()).to_string().as_bytes());
        false
    }

    /// THE ONE PICKUP (iOS fetchBox; Android fetchOnce): the invitations' boxes and every pipe's, across the term, and the pipe
    /// of this person's devices under this machine's own name (iOS BoxEar: the store yields no letter to the sid that laid it,
    /// so its own letters stay for the others); the count landed.
    pub fn fetch_once(&self) -> usize {
        let w0 = wire::day();
        let mut subs: Vec<(String, Vec<u8>, From, String)> = vec![]; // label, secret, whose box, sid
        for inv in (Card { vault: self.vault }).outstanding_invites() {
            let s = rdv_letter_secret(&inv).to_vec();
            for w in (w0 - 8)..=(w0 + 1) {
                let cw = rdv_conv_w(&inv, w);
                let sid = sub_id(&cw, &self.twin);
                subs.push((cw, s.clone(), From::Invite(b64url(&inv)), sid));
            }
        }
        for r in self.book.refs() {
            let Some(s) = self.book.secret(&r) else { continue };
            for w in (w0 - 8)..=(w0 + 1) {
                let cw = conv_w(&s, w);
                let sid = sub_id(&cw, &self.twin);
                subs.push((cw, s.clone(), From::Pipe(r.clone()), sid));
            }
        }
        let me = self.twin_me();
        if let Some(me) = &me {
            for w in (w0 - 8)..=(w0 + 1) {
                let cw = conv_w(&me.secret, w);
                let sid = sub_id(&cw, &me.name);
                subs.push((cw, me.secret.to_vec(), From::Twin, sid));
            }
        }
        for (key, s) in crate::keeping::listening(self) {
            for w in (w0 - 8)..=(w0 + 1) {
                let cw = conv_w(&s, w);
                let sid = sub_id(&cw, &self.twin);
                subs.push((cw, s.clone(), From::Keep(key.clone()), sid));
            }
        }
        let mut landed = 0;
        let mut taken: Vec<String> = vec![];
        for chunk in subs.chunks(128) {
            let page = json!({
                "subs": chunk.iter().map(|x| x.0.clone()).collect::<Vec<_>>(),
                "sids": chunk.iter().map(|x| x.3.clone()).collect::<Vec<_>>(),
            });
            let mut seen = std::collections::HashSet::new();
            let mut rows: Vec<Value> = vec![];
            for (code, v) in doors::read_each("/fetch", &page, 6000) {
                if code != 200 {
                    continue;
                }
                for l in v.as_ref().and_then(|v| v["letters"].as_array()).cloned().unwrap_or_default() {
                    if seen.insert(l["m"].as_str().unwrap_or("").to_string()) {
                        rows.push(l);
                    }
                }
            }
            for l in rows {
                let cw = l["c"].as_str().unwrap_or("");
                let Some((_, secret, inv_or_chat, _)) = chunk.iter().find(|x| x.0 == cw) else { continue };
                let Some(sealed) = l["e"].as_str().and_then(unb64) else { continue };
                let Some(plain) = wire::open_boxed(&sealed, secret, l["at"].as_i64().unwrap_or(wire::now_ms() / 1000)) else { continue };
                let one = LANDING.lock().unwrap_or_else(|e| e.into_inner());
                let ok = match inv_or_chat {
                    From::Invite(inv) => self.first(&plain, inv),
                    From::Pipe(r) => self.letter(r, &plain, secret),
                    From::Twin => me.as_ref().is_some_and(|me| self.twin_takes(me, &plain)),
                    From::Keep(key) => crate::keeping::takes(&self.twin, key, &plain),
                };
                drop(one);
                if ok {
                    landed += 1;
                    if let Some(m) = l["m"].as_str().filter(|m| !m.is_empty()) {
                        taken.push(m.to_string());
                    }
                }
            }
        }
        if !taken.is_empty() {
            let body = json!({ "mids": taken });
            for door in doors::all() {
                doors::post_at(&door, "/box-del", &body, 5000);
            }
        }
        landed
    }

    /// The words of a long letter (iOS fetchLongV): the blob from any store, opened under the key the envelope carried. Err(true)
    /// when every store said it is gone, Err(false) when it may still come.
    pub(crate) fn fetch_long(&self, word: &str) -> Result<String, bool> {
        let Some(o) = word.strip_prefix(marks::LONG).and_then(|j| serde_json::from_str::<Value>(j).ok()) else { return Err(true) };
        let (Some(bid), Some(key)) = (o["r"].as_str(), o["k"].as_str().and_then(unb64)) else { return Err(true) };
        let (mut gone, mut found) = (true, None);
        doors::read_machines("/blob-get", &json!({ "bid": bid }), http::POST_DEADLINE_MS, |code, v| {
            if code == 200 {
                found = v.as_ref().and_then(|v| v["data"].as_str()).and_then(unb64);
            }
            if code != 404 {
                gone = false;
            }
            found.is_some()
        });
        let Some(sealed) = found else { return Err(gone) };
        let Some(plain) = crypto::open(&key, &sealed) else { return Err(true) };
        let at = plain.iter().position(|&b| b == 0).map_or(plain.len(), |i| i + 1);
        Ok(String::from_utf8_lossy(&plain[at..]).into_owned())
    }

    /// A long letter of theirs is due again (iOS lbDueNow): the hour its blob is asked next has come.
    fn long_due(&self, mid: &str) -> bool {
        jmap(self.vault, LONG_WAIT).get(mid).and_then(|w| w["next"].as_i64()).is_none_or(|n| n <= wire::now_ms() / 1000)
    }

    fn long_forget(&self, mid: &str) {
        let mut m = jmap(self.vault, LONG_WAIT);
        if m.remove(mid).is_some() {
            self.vault.set(LONG_WAIT, Value::Object(m).to_string().as_bytes());
        }
    }

    /// The blob did not come (iOS lbFailed): it waits in the box, asked again later and later (15 s doubling to an hour); gone
    /// three times over ten minutes, or older than the box's day, it is buried; the writer is told once that it is gone.
    fn long_failed(&self, r: &str, mid: &str, gone: bool) -> bool {
        let now = wire::now_ms() / 1000;
        let mut m = jmap(self.vault, LONG_WAIT);
        let mut w = m.get(mid).cloned().unwrap_or_else(|| json!({ "born": birth_ms(mid).map_or(now, |b| b / 1000), "tries": 0, "goneN": 0 }));
        let born = w["born"].as_i64().unwrap_or(now);
        if gone {
            if w["goneN"].as_i64().unwrap_or(0) == 0 {
                w["goneAt"] = json!(now);
            }
            w["goneN"] = json!(w["goneN"].as_i64().unwrap_or(0) + 1);
        }
        let bury = (w["goneN"].as_i64().unwrap_or(0) >= 3 && now - w["goneAt"].as_i64().unwrap_or(now) >= 600) || now - born > 86_400;
        if bury {
            m.remove(mid);
        } else {
            if gone && !w["told"].as_bool().unwrap_or(false) {
                w["told"] = json!(true);
                self.deliver(r, &mint_mid(), &format!("{}{mid}", marks::CARGO_GONE));
            }
            let tries = w["tries"].as_i64().unwrap_or(0);
            w["next"] = json!(now + (15i64 << tries.min(8)).min(3600));
            w["tries"] = json!(tries + 1);
            m.insert(mid.to_string(), w);
        }
        self.vault.set(LONG_WAIT, Value::Object(m).to_string().as_bytes());
        bury
    }

    /// THE FIRST LETTER OF A MEETING (iOS drainInbox «rdv» + MontanaCard.accept): ct[1088] ‖ mid‖0 text‖0 name‖0 glyph‖0 conf‖0.
    fn first(&self, plain: &[u8], inv64: &str) -> bool {
        if plain.len() <= 1092 {
            return false;
        }
        let ct = &plain[..1088];
        let f = wire::fields(plain, 1088, 7);
        if f[0].is_empty() || f[1].is_empty() {
            return false;
        }
        let mut text = f[1].clone();
        if text.starts_with(marks::LONG) {
            match self.fetch_long(&text) {
                Ok(w) => text = w,
                Err(_) => return false, // the blob may come later: the letter stays in the box
            }
        }
        let Some((secret, root)) = (Card { vault: self.vault }).accept_first(ct, inv64, &f[4]) else { return true }; // not ours: buried
        let Some(r) = self.book.establish(&secret) else { return false };
        if doors::barred(&r) {
            return true; // barred by the network (iOS refuses): no conversation opens, the letter is buried
        }
        let name = Some(f[2].trim()).filter(|n| !n.is_empty() && n.chars().count() <= 64).map(strip_crown).unwrap_or_default();
        let fresh = self.book.chat(&r).is_none();
        self.book.open(&r, &name, (Card { vault: self.vault }).is_permanent_root(&root));
        if fresh {
            self.read_pipe_face(&r, &secret);
        }
        self.mirror_heard(&r, &f[0], &text, "", "", "");
        self.place(&r, &f[0], &text, &f[2], "", "", "", false);
        self.announce(&r);
        true
    }

    /// A letter the lane carried (iOS epoch «letter»: the sender's raw box envelope while my chat was open): opened as the
    /// box opens it, landed as a box letter; a copy the box brings later is heard before and answered only.
    pub fn lane_letter(&self, r: &str, sealed: &[u8]) -> bool {
        let Some(secret) = self.book.secret(r) else { return false };
        let Some(plain) = wire::open_boxed(sealed, &secret, wire::now_ms() / 1000) else { return false };
        let _one = LANDING.lock().unwrap_or_else(|e| e.into_inner());
        self.letter(r, &plain, &secret)
    }

    /// A LETTER OFF A CHANNEL (iOS Post.fromChannel): the pipe's own letter, opened by the pipe's key, lands as a box letter does;
    /// the box's copy that comes later is heard before and answered only.
    pub fn channel_letter(&self, r: &str, plain: &[u8]) -> bool {
        let Some(secret) = self.book.secret(r) else { return false };
        let _one = LANDING.lock().unwrap_or_else(|e| e.into_inner());
        self.letter(r, plain, &secret)
    }

    /// A letter under a pipe's label: a person's word becomes a row, a word of the wire changes the feed.
    fn letter(&self, r: &str, plain: &[u8], secret: &[u8]) -> bool {
        let f = wire::fields(plain, 0, 8);
        if f[0].is_empty() || f[1].is_empty() {
            return false;
        }
        let own = !f[7].is_empty() && wire::author_holds(&f[7], self.author_key.as_deref(), secret, &f[0], &f[1]);
        if own {
            // THE PERSON'S OWN LETTER FROM ANOTHER OF THEIR DEVICES (iOS receive → landOwn): mine, whichever device wrote it
            let mut text = f[1].clone();
            if text.starts_with(marks::LONG) {
                match self.fetch_long(&text) {
                    Ok(w) => text = w,
                    Err(gone) => return gone,
                }
            }
            self.land_own(r, &f[0], &text, &f[4], &f[5], &f[6]);
            return true;
        }
        if self.book.chat(r).is_some_and(|c| c.blocked) || doors::barred(r) {
            return true; // THE ONE QUESTION EVERY ROAD ASKS (iOS ChatStore.refuses): taken from the box, said nothing
        }
        meeting::first_done(self.vault, r); // a word sealed under the pipe by the other side: the introduction is over
        let mut text = f[1].clone();
        if text.starts_with(marks::LONG) {
            if !self.long_due(&f[0]) {
                return false;
            }
            match self.fetch_long(&text) {
                Ok(w) => {
                    self.long_forget(&f[0]);
                    text = w;
                }
                Err(gone) => return self.long_failed(r, &f[0], gone),
            }
        }
        self.mirror_heard(r, &f[0], &text, &f[4], &f[5], &f[6]);
        self.place(r, &f[0], &text, &f[2], &f[4], &f[5], &f[6], false);
        if !f[7].is_empty() && marks::is_row(&text) {
            let (mid, au) = (f[0].clone(), f[7].clone());
            self.book.edit(r, |c| { if let Some(m) = c.msgs.iter_mut().find(|m| !m.mine && m.mid == mid) { m.author = au; } });
        }
        true
    }

    /// A word applied to a chat as if it came on it (a group's answers: reactions, edits, deletions, pins).
    pub fn place_word(&self, r: &str, text: &str) {
        self.place(r, &mint_mid(), text, "", "", "", "", false);
    }

    /// A correspondent's word another device of the person took (the twin mirror): it lands as if it came here, answers nobody.
    pub(crate) fn place_quiet(&self, r: &str, mid: &str, text: &str, qt: &str, qm: &str, lp: &str) {
        self.place(r, mid, text, "", qt, qm, lp, true);
    }

    #[allow(clippy::too_many_arguments)]
    fn place(&self, r: &str, mid: &str, text: &str, name: &str, qt: &str, qm: &str, lp: &str, quiet: bool) {
        let lp = crate::linkcard::parse(lp).filter(|c| crate::linkcard::urls(text).iter().any(|u| Some(u.as_str()) == c["u"].as_str()))
            .map(|c| c.to_string()).unwrap_or_default();   // a card stands under the letter whose words hold its link
        let receipt = |r: &str, mid: &str| {
            if !quiet {
                self.receipt(r, mid);
            }
        };
        if text.starts_with(crate::groups::MARK) {
            self.group_word(r, mid, text); // a group word on this pipe: the group's, never this chat's
            return;
        }
        if text.starts_with(crate::stickers::MARK) {
            if !quiet {
                crate::stickers::heard(self, self.media, r, text); // a set's word (iOS MontanaStickerWire): never a row
            }
            return;
        }
        // THE FABRIC OF TIME (iOS MTFabric): its word is a testimony the correspondent signed, never a row, never receipted; a live
        // act of theirs may be answered by one -- by the machine that took it from the box, never by the mirror's copy
        if let Some(t) = text.strip_prefix(crate::fabric::MARK) {
            if let (false, Some(s)) = (quiet, self.book.secret(r)) {
                crate::fabric::received(t, r, &s);
            }
            return;
        }
        if let (false, true, Some(s)) = (quiet, crate::fabric::is_live_act(text), self.book.secret(r)) {
            crate::fabric::heard(r, &s);
        }
        if text.starts_with(crate::keeping::MARK) {
            if !quiet {
                crate::keeping::heard(&self.twin, r, text); // the keeping of a copy (iOS MTKeeping.heard): never a row
            }
            return;
        }
        if text.starts_with(crate::pageground::MARK) {
            if !quiet {
                // their page's ground (iOS MTPageGround.note): kept, the latest word winning; never a row
                crate::pageground::note(self.vault, r, text, &|name: &str, b: &[u8]| self.media.put(name, b));
            }
            receipt(r, mid);
            return;
        }
        if text.starts_with(crate::board::MARK) {
            if !quiet {
                self.wall_word(r, text); // a word of the wall (iOS MTBoard.handle): never a row
            }
            receipt(r, mid);
            return;
        }
        if let Some(d) = text.strip_prefix(marks::DELIVERED) {
            if self.group_receipt(d) {
                return; // the receipt of a copy of a group word
            }
            // the receipt; the read word may have outrun it (iOS markDelivered 4221-4226); a receipt of my name records it said;
            // the receipt of my erasure for both ends the pipe
            let mut ended = false;
            self.book.edit(r, |c| {
                let f: Vec<String> = c.name_flight.split('\n').map(str::to_string).collect();
                if f.len() == 3 && f[1] == d {
                    c.announced = f[0].clone();
                    c.name_flight.clear();
                }
                let f: Vec<String> = c.face_flight.split('\n').map(str::to_string).collect();
                if f.len() == 3 && f[1] == d {
                    c.face_said = f[0].clone();
                    c.face_flight.clear();
                }
                let f: Vec<String> = c.about_flight.split('\n').map(str::to_string).collect();
                if f.len() == 3 && f[1] == d {
                    c.about_said = f[0].clone();
                    c.about_flight.clear();
                }
                ended = !c.funeral_mid.is_empty() && c.funeral_mid == d;
                let upto = c.peer_read;
                if let Some(m) = c.msgs.iter_mut().find(|m| m.mine && m.mid == d) {
                    if m.advance(2) && birth_ms(&m.mid).is_some_and(|b| b <= upto) {
                        m.advance(3);
                    }
                }
            });
            if ended && self.book.chat(r).is_some_and(|c| c.msgs.is_empty()) {
                self.book.drop_chat(r);
            }
            return;
        }
        if let Some(rest) = text.strip_prefix(marks::READ) {
            // «read» only onto what was delivered: the bulk word never paints a letter they do not have (Android 1607-1612)
            let upto = rest.trim().parse::<i64>().ok();
            self.book.edit(r, |c| {
                if let Some(u) = upto {
                    c.peer_read = c.peer_read.max(u);
                }
                for m in c.msgs.iter_mut().filter(|m| m.mine && upto.is_none_or(|u| birth_ms(&m.mid).unwrap_or(0) <= u)) {
                    m.advance(3);
                }
            });
            return;
        }
        if let Some(n) = text.strip_prefix(marks::NAME) {
            let n = strip_crown(n.trim());
            if !n.is_empty() && n.chars().count() <= 64 {
                self.book.edit(r, |c| c.name = n);
            }
            receipt(r, mid);
            return;
        }
        if let Some(b) = text.strip_prefix(marks::AVATAR) {
            // their face, in the order it was spoken (iOS stateIsCurrent): an empty word takes it back; always answered. A face word
            // in yesterday's shapes (manifest or rm JSON) is buried unread (iOS applyIncomingAvatar): reading it as «no face» erased
            // the present face. The face is taken whole, as iOS takes it (a cap of 4 MB guards the memory alone).
            let at = birth_ms(mid).unwrap_or(0);
            if !b.starts_with('{') && self.book.chat(r).is_some_and(|c| at >= c.face_at) {
                if b.is_empty() {
                    self.faces.delete(r);
                    self.book.edit(r, |c| c.face_at = at);
                } else if let Some(f) = unb64(b).filter(|f| !f.is_empty() && f.len() <= 4 * 1_048_576 && *f != self.self_face) {
                    if self.wear_face(r, &f) {
                        self.book.edit(r, |c| c.face_at = at.max(1));
                    }
                }
            }
            receipt(r, mid);
            return;
        }
        if crate::presence::is_lane_word(text) {
            // a presence word that rode the box (iOS: the block's «AP:0B» is durable): the ladder, never a row
            self.presence.hear(r, text, false);
            return;
        }
        if let Some(j) = text.strip_prefix(marks::ABOUT) {
            // their words about themselves, the newest kept (iOS PeerAbout.note); always answered
            if let Ok(o) = serde_json::from_str::<Value>(j) {
                let at = o["at"].as_f64().unwrap_or(0.0);
                if let Some(k) = o["k"].as_str() {
                    crate::wallet::note_peer_from(self.vault, r, k); // their coin key: my SEND commits to it
                }
                // a word with the coin key alone says nothing of the bio (iOS ChatStore 4620): b and l stand only when told
                if o.get("b").is_some() || o.get("l").is_some() {
                    let bio: String = o["b"].as_str().unwrap_or("").chars().take(140).collect();
                    let link = crate::profile::kept_link(o["l"].as_str().unwrap_or(""));
                    self.book.edit(r, |c| {
                        if at >= c.peer_about_at {
                            c.peer_about_at = at;
                            c.peer_bio = bio;
                            c.peer_link = link;
                        }
                    });
                }
                // THEIR SEND FOUND NO KEY OF MINE (iOS «q», 21.10.2026): the word they hold is lost or never came -- told again now
                if o.get("q").is_some() {
                    crate::wallet::forget_told_key(self.vault, r);
                    self.announce_about(r);
                }
            }
            receipt(r, mid);
            return;
        }
        if let Some(payload) = text.strip_prefix(marks::DELETE) {
            // taken away for both: the row leaves, the name is buried even before the row came (iOS 4500-4523); no receipt
            let d = bare(payload).to_string();
            if !d.is_empty() {
                // THE PERSON KEEPS WHAT OTHERS DELETE (iOS MTLevelAccess.keepDeleted, level 7): a letter this machine holds stays,
                // and the correspondent is told -- their machine never believes a deletion that did not happen here
                let held = self.book.chat(r).is_some_and(|c| c.msgs.iter().any(|m| m.mid == d));
                if held && crate::person::keeps_deleted(self.vault) {
                    crate::trace_line("delete_kept kept by the person's choice (level access)");
                    if !quiet && !crate::groups::is_group(r) {
                        self.word_kept(r, &mint_mid(), &format!("{}{payload}", marks::KEPT));
                    }
                    return;
                }
                self.book.edit(r, |c| c.bury(&d));
            }
            return;
        }
        if text.starts_with(marks::KEPT) {
            // my deletion was kept there: the keeper's own word, told to the person (iOS MontanaNotify.presentKept)
            if !quiet {
                self.news.lock().unwrap().push(News { chat: r.to_string(), text: marks::KEPT.to_string(), anon: None });
            }
            return;
        }
        if let Some(j) = text.strip_prefix(marks::EDIT) {
            // their new words for their own letter, never for mine (iOS 3715-3751); held while the letter is on its way
            let o: Value = serde_json::from_str(j).unwrap_or(Value::Null);
            let (sid, tx) = (bare(o["sid"].as_str().unwrap_or("")).to_string(), o["tx"].as_str().unwrap_or("").to_string());
            if sid.is_empty() || sid.len() > 128 || tx.trim().is_empty() || tx.chars().count() > 4500 || marks::is_service(&tx) {
                return;
            }
            self.book.edit(r, |c| match c.msgs.iter_mut().find(|m| m.mid == sid) {
                Some(m) if !m.mine && !marks::is_service(&m.text) => {
                    m.text = tx;
                    m.edited = true;
                }
                Some(_) => {}
                None => {
                    c.held_edits.retain(|(s, _)| *s != sid);
                    c.held_edits.push((sid, tx));
                    if c.held_edits.len() > 32 {
                        c.held_edits.remove(0);
                    }
                }
            });
            return;
        }
        if let Some(j) = text.strip_prefix(marks::PIN) {
            // their pin (iOS ChatStore 6334-6351): by the letter's name, by its words when no name came
            let o: Value = serde_json::from_str(j).unwrap_or(Value::Null);
            let (sid, txt, op) = (bare(o["sid"].as_str().unwrap_or("")).to_string(), o["txt"].as_str().unwrap_or(""), o["op"].as_str().unwrap_or(""));
            self.book.edit(r, |c| {
                let at = c.msgs.iter().find(|m| m.mid == sid).or_else(|| c.msgs.iter().rev().find(|m| m.text == txt)).map(|m| m.mid.clone());
                match at {
                    Some(mid) => {
                        c.pins.retain(|p| *p != mid);
                        if op == "pin" {
                            c.pins.push(mid);
                        }
                    }
                    // the pin came before its letter (the box hands them in its own order): held until the letter lands
                    None if op == "pin" && !sid.is_empty() => {
                        c.held_edits.retain(|(s, _)| *s != format!("pin:{sid}"));
                        c.held_edits.push((format!("pin:{sid}"), String::new()));
                    }
                    None => c.held_edits.retain(|(s, _)| *s != format!("pin:{sid}")),
                }
            });
            return;
        }
        if let Some(j) = text.strip_prefix(marks::REACT) {
            // their one answer to a letter (iOS 6310-6367): by the letter's name, by its words only when no name came
            let o: Value = serde_json::from_str(j).unwrap_or(Value::Null);
            let (sid, txt, e, op) = (bare(o["sid"].as_str().unwrap_or("")).to_string(), o["txt"].as_str().unwrap_or(""),
                                     o["e"].as_str().unwrap_or("").to_string(), o["op"].as_str().unwrap_or(""));
            if op == "coin3" {
                // A PAID REACTION IS A SEND OF THE CHAIN (iOS 2304 ChatStore 6606): the word names the SEND and its letter; the coins
                // come by the scan
                if let (Some(tx), false) = (o["tx"].as_str(), sid.is_empty() || crate::groups::is_group(r)) {
                    crate::wallet::heard(self.vault, tx, &format!("mid:{sid}"));
                }
                return;
            }
            if op == "coin" {
                // COINS GIVEN ON A LETTER (iOS MTCoinSend.reacted): credited once by the name the word carries, never an emoji
                if let (Some(c), Some(rf), false) = (o["c"].as_i64().filter(|c| *c > 0), o["r"].as_str().filter(|x| !x.is_empty()), sid.is_empty()) {
                    if !crate::groups::is_group(r) && crate::coins::moved(self.vault, "receive", c, &format!("rc:{rf}"), Some(r), Some(&format!("mid:{sid}"))) {
                        crate::trace_line(&format!("coin_reaction received coins={c}"));
                    }
                }
                return;
            }
            if e.is_empty() || e.chars().count() > 16 {
                return;
            }
            self.book.edit(r, |c| {
                let at = if sid.is_empty() { c.msgs.iter().rposition(|m| m.text == txt) } else { c.msgs.iter().position(|m| m.mid == sid) };
                if let Some(m) = at.map(|i| &mut c.msgs[i]) {
                    match op {
                        "add" => m.peer_react = e,
                        "del" if m.peer_react == e => m.peer_react.clear(),
                        _ => {}
                    }
                }
            });
            return;
        }
        if text.starts_with(marks::CONVDEL) {
            // THEIR FUNERAL OF THE CONVERSATION (iOS peerFuneral 2032-2087): answered first; what was born before it leaves; a
            // letter of theirs born after it keeps the conversation standing
            receipt(r, mid);
            let Some(fu) = birth_ms(mid) else { return };
            self.book.edit(r, |c| {
                if fu <= c.funeral {
                    return;
                }
                c.funeral = fu;
                let later = c.msgs.iter().any(|m| !m.mine && m.at > fu);
                c.msgs.retain(|m| m.at > fu);
                c.unread = c.unread.min(c.msgs.iter().filter(|m| !m.mine).count() as u32);
                if !later {
                    c.msgs.clear();
                    c.unread = 0;
                    c.hidden = true;
                }
            });
            return;
        }
        if text.starts_with(crate::calls::RING) {
            self.heard_ring(r, text); // a call rings by the box: no row, no receipt (iOS)
            return;
        }
        if text.starts_with(crate::calls::MISSED) {
            self.heard_missed(r, mid, text, !quiet);
            return;
        }
        if !marks::is_row(text) {
            return; // a word of the wire this build does not apply (pins, presence, faces...): never a row
        }
        let at = birth_ms(mid).unwrap_or_else(wire::now_ms);
        // a row the other device's blocks gave back under the archive's name is this very letter: it takes its wire name
        if self.book.chat(r).is_some_and(|c| c.msgs.iter().any(|m| m.mid.starts_with("arc:") && !m.mine && m.text == text)) {
            self.book.edit(r, |c| { crate::twin::arc_rename(c, mid, text, false, at); });
        }
        let chat = self.book.chat(r);
        let heard = chat.as_ref().is_some_and(|c: &Chat| c.msgs.iter().any(|m| m.mid == mid));
        let buried = chat.as_ref().is_some_and(|c| c.graves.iter().any(|g| g == mid) || (c.funeral > 0 && at <= c.funeral));
        if heard && !lp.is_empty() {
            // a copy that brought the card the row lacks, or its picture: the card settles onto it (iOS enrichLinkPreview)
            self.book.edit(r, |c| {
                if let Some(m) = c.msgs.iter_mut().find(|m| m.mid == mid) {
                    if let Some(card) = crate::linkcard::enrich(&m.lp, &lp) {
                        m.lp = card;
                    }
                }
            });
        }
        if heard || buried {
            if !text.starts_with(marks::MEDIA) || heard {
                receipt(r, mid); // heard before or taken away: their phone did not hear my receipt; never a second row
            }
            return;
        }
        let named = strip_crown(name.trim());
        self.presence.landed(r);   // their live words that became this letter leave the screen
        let row = Msg { mid: mid.to_string(), text: text.to_string(), mine: false, at, qt: first_chars(qt, 200), qm: qm.to_string(), lp, ..Default::default() };
        self.book.edit(r, |c| {
            if c.name.is_empty() && !named.is_empty() {
                c.name = named.clone();
            }
            let mut row = row;
            if let Some(i) = c.held_edits.iter().position(|(s, _)| *s == row.mid) {
                row.text = c.held_edits.remove(i).1;
                row.edited = true;
            }
            if let Some(i) = c.held_edits.iter().position(|(s, _)| *s == format!("pin:{}", row.mid)) {
                c.held_edits.remove(i);
                c.pins.push(row.mid.clone());
            }
            c.msgs.push(row);
            c.msgs.sort_by_key(|m| m.at);
            if !crate::chess::is_step(text) {
                c.unread += 1; // a game's step stands on its board, never among the unread (iOS isChessStep)
            }
            c.hidden = false;
            c.marked = false;
        });
        if !crate::chess::is_step(text) || crate::chess::rings(text) {
            self.news.lock().unwrap().push(News { chat: r.to_string(), text: text.to_string(), anon: None });
        }
        self.archive_row(r, false, at, mid, text);
        self.mint_letter(r, mid, text, at);
        // A CHOSEN PERSON'S LETTER IS PAID BY ITSELF (iOS MTAutoReact.landed): a fresh letter born after the choice, once by its name
        if !quiet {
            if let Some(c) = crate::coins::auto_react(self.vault, r).filter(|(_, since)| *since <= at as f64 / 1000.0 && wire::now_ms() - at <= 86_400_000).map(|(c, _)| c) {
                if crate::coins::letter_of(text).is_none() && !crate::chess::is_step(text) && !crate::groups::is_group(r) {
                    // with the coin key in hand the pay is a SEND the coin walk lays (wallet::auto_queue); else the book's road of before
                    let paid = if crate::coin_chain_on() && crate::wallet::held_hands().is_some() {
                        crate::wallet::auto_queue(self.vault, r, mid, c)
                    } else {
                        self.give(r, mid, c, &format!("auto:mid:{mid}"), None)
                    };
                    crate::trace_line(&format!("auto_react coins={c} paid={}", paid as u8));
                }
            }
        }
        // A COIN LETTER OF AN OLDER BUILD (iOS MTCoinLetter, MTCoinSend.settle): credited once by its wire name, when it names itself
        if let Some((c, id)) = crate::coins::letter_of(text).filter(|_| !crate::groups::is_group(r)) {
            if crate::coins::bound(&id, mid) {
                crate::coins::moved(self.vault, "receive", c, &format!("mid:{mid}"), Some(r), None);
            }
        }
        // the receipt: «delivered» goes back under the pipe (iOS receipt); a picture's only once its file is whole
        if !text.starts_with(marks::MEDIA) {
            receipt(r, mid);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::seed;

    #[test]
    fn the_words_of_the_wire_ring_or_stay_silent_as_on_ios() {
        assert!(marks::is_silent(&format!("{}{}", marks::DELETE, "mid:t1-A")));
        assert!(marks::is_silent(marks::CONVDEL) && marks::is_silent(&format!("{}5", marks::READ)));
        assert!(!marks::is_silent("привет") && !marks::is_silent(&format!("{}{{}}", marks::MEDIA)));
        assert!(!marks::is_silent(&format!("{}🔥", marks::STICKER)) && marks::is_row(&format!("{}🔥", marks::STICKER)));
        assert!(!marks::is_row(marks::CONVDEL) && !marks::is_row(&format!("{}x", marks::NAME)));
    }

    fn person(root: &std::path::Path, n: &str) -> (Vault, String, String) {
        let v = Vault::at(&root.join(n)).unwrap();
        let words = seed::generate().unwrap();
        let twin = seed::twin_of(&words).unwrap();
        (v, words, twin)
    }

    /// Two people on the live network, each with a vault of their own: Alice hands out her card, Bob meets it and writes,
    /// Alice reads the first letter and answers under the pipe, Bob reads the answer; the receipts walk back; then a long
    /// letter, a reply, an edit, a reaction and a deletion for both. Run with --ignored and MONTANA_LIVE=1: it speaks to
    /// Montana's nodes with throw-away identities.
    #[test]
    #[ignore]
    fn alice_and_bob_meet_by_a_card_and_write_both_ways() {
        let root = std::env::temp_dir().join(format!("montana-post-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (va, wa, ta) = person(&root, "alice");
        let (vb, wb, tb) = person(&root, "bob");
        let (ba, bb) = (Book::new(va.clone()), Book::new(vb.clone()));
        let (sa, sb) = (media::Store::at(&root.join("alice-media")).unwrap(), media::Store::at(&root.join("bob-media")).unwrap());
        let (pa, pb) = (crate::presence::Presence::default(), crate::presence::Presence::default());
        let alice = Desk { vault: &va, book: &ba, twin: ta, author_key: seed::author_key_of(&wa), my_name: "Alice".into(), news: Default::default(), media: &sa, faces: &sa, self_face: vec![], about: Default::default(), read_receipts: true, presence: &pa, archive: None };
        let bob = Desk { vault: &vb, book: &bb, twin: tb, author_key: seed::author_key_of(&wb), my_name: "Bob".into(), news: Default::default(), media: &sb, faces: &sb, self_face: vec![], about: Default::default(), read_receipts: true, presence: &pb, archive: None };
        let wait = |who: &Desk, ok: &dyn Fn() -> bool| {
            for _ in 0..20 {
                who.fetch_once();
                if ok() {
                    return true;
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
            }
            false
        };

        let link = (Card { vault: &va }).offer_permanent("Alice").unwrap();
        // the card goes up off-thread: Bob waits until it unfolds
        let mut met = meeting::Outcome::Refused;
        for _ in 0..10 {
            met = meeting::meet(&vb, &bb, &link);
            if matches!(met, meeting::Outcome::Opened(_)) { break; }
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
        let meeting::Outcome::Opened(rb) = met else { panic!("Bob could not meet Alice's card: {met:?}") };
        assert_eq!(bb.chat(&rb).unwrap().name, "Alice");
        // the first letter is long: it rides the invitation's box as a blob
        let first = format!("Привет, Алиса! Это Windows. {}", "Длинное первое письмо. ".repeat(40));
        bob.send(&rb, &first);
        assert_eq!(bb.chat(&rb).unwrap().msgs[0].state, 1, "no node boxed Bob's first letter");

        assert!(wait(&alice, &|| ba.all().iter().any(|c| !c.msgs.is_empty())), "Alice never received Bob's first letter");
        let ra = ba.all().into_iter().find(|c| !c.msgs.is_empty()).unwrap().reference;
        let ca = ba.chat(&ra).unwrap();
        assert_eq!((ca.name.as_str(), ca.msgs[0].text.as_str()), ("Bob", first.as_str()));
        assert_eq!(ra, rb, "both sides file the pipe under the same reference");

        // Alice answers with a reply to it
        let bobs = ca.msgs[0].mid.clone();
        let mid = alice.draft(&ra, "Привет, Боб! Письмо дошло.", "Привет, Алиса!", &bobs);
        assert!(alice.post(&ra, &mid));
        assert!(wait(&bob, &|| bb.chat(&rb).unwrap().msgs.iter().any(|m| !m.mine && m.qm == bobs)), "Bob never received Alice's reply");
        assert!(meeting::first(&vb, &rb).is_none(), "Alice's word under the pipe ended the introduction");
        assert!(wait(&bob, &|| bb.chat(&rb).unwrap().msgs.iter().any(|m| m.mine && m.state >= 2)), "Alice's receipt never reached Bob");

        // Bob reads Alice's answer: her letter turns «read» on her side, his name stands in her chat
        bob.mark_read(&rb);
        assert_eq!(bb.chat(&rb).unwrap().unread, 0);
        assert!(wait(&alice, &|| ba.chat(&ra).unwrap().msgs.iter().any(|m| m.mine && m.state == 3)), "Bob's read mark never reached Alice");
        assert!(wait(&alice, &|| ba.chat(&ra).unwrap().announced == "Alice"), "Bob's receipt of Alice's name records it said");

        // a long letter under the pipe, an edit, a reaction, then Alice takes her letter away for both
        let long = "Строка длинного письма. ".repeat(120);
        let lm = alice.send(&ra, &long);
        assert!(wait(&bob, &|| bb.chat(&rb).unwrap().msgs.iter().any(|m| m.text == long)), "Bob never unfolded the long letter");
        assert!(alice.edit_letter(&ra, &mid, "Привет, Боб! Письмо дошло (правка)."));
        assert!(wait(&bob, &|| bb.chat(&rb).unwrap().msgs.iter().any(|m| m.edited && m.text.ends_with("(правка)."))), "the edit never came");
        bob.react(&rb, &mid, "🔥");
        assert!(wait(&alice, &|| ba.chat(&ra).unwrap().msgs.iter().any(|m| m.peer_react == "🔥")), "the reaction never came");
        alice.pin(&ra, &mid, true, true);
        assert!(wait(&bob, &|| bb.chat(&rb).unwrap().pins.contains(&mid)), "the pin never came");
        alice.delete(&ra, std::slice::from_ref(&lm), true);
        assert!(wait(&bob, &|| !bb.chat(&rb).unwrap().msgs.iter().any(|m| m.mid == lm)), "the deletion never came");

        // a file of 1.2 MB in three pieces: Bob's goes up, Alice's comes whole, Bob's letter turns «delivered»
        let file: Vec<u8> = (0..1_200_000u32).map(|i| (i % 251) as u8).collect();
        let fm = bob.draft_media(&rb, &file, json!({ "k": "doc", "e": "bin", "n": "проба.bin" }), "", "").unwrap();
        assert!(bob.post(&rb, &fm), "Bob's file did not go up");
        assert!(wait(&alice, &|| ba.chat(&ra).unwrap().msgs.iter().any(|m| m.mid == fm)), "the file's letter never came");
        for _ in 0..5 {
            if alice.fetch_media(None, u64::MAX) { break; }
        }
        assert_eq!(sa.get(&fm).as_deref(), Some(file.as_slice()), "Alice's file is not Bob's");
        assert!(wait(&bob, &|| bb.chat(&rb).unwrap().msgs.iter().any(|m| m.mid == fm && m.state >= 2)), "no receipt for the file");

        // a link with its card: Alice's machine reads the page itself, the card rides seventh in the envelope, Bob holds it
        let page = "https://github.com/efir369999/montana_messenger";
        let card = crate::linkcard::build(page).expect("the page gave no card");
        assert!(card["t"].as_str().is_some_and(|t| !t.is_empty()), "a card says something: {card}");
        let lk = alice.draft(&ra, &format!("Код Montana: {page}"), "", "");
        ba.edit(&ra, |c| { if let Some(m) = c.msgs.iter_mut().find(|m| m.mid == lk) { m.lp = card.to_string(); } });
        assert!(alice.post(&ra, &lk));
        assert!(wait(&bob, &|| bb.chat(&rb).unwrap().msgs.iter().any(|m| m.mid == lk && crate::linkcard::parse(&m.lp).is_some_and(|c| c["u"] == page && c["t"] == card["t"]))),
                "Bob never held the card");

        // Alice shows a face: it rides long (LB:), lands as Bob's picture of her, and his receipt records it said
        let face: Vec<u8> = [0xFF, 0xD8].into_iter().chain((0..60_000u32).map(|i| (i % 253) as u8)).collect();
        let alice_faced = Desk { self_face: face.clone(), news: Default::default(), twin: alice.twin.clone(), author_key: alice.author_key.clone(),
                                 my_name: alice.my_name.clone(), ..alice };
        alice_faced.announce_face(&ra);
        assert!(wait(&bob, &|| sb.get(&rb).as_deref() == Some(face.as_slice())), "Bob never saw Alice's face");
        assert!(wait(&alice_faced, &|| ba.chat(&ra).unwrap().face_said == face_tag(&face)), "Bob's receipt of the face never came");
        let _ = std::fs::remove_dir_all(&root);
    }

    /// THE HISTORY ROAD, LIVE: Alice and Bob meet and write; Alice's archive keeps it; her copy, laid back on a fresh machine
    /// with the same words, gives the pipe, Bob's name and the letters back -- and the fresh machine writes to Bob under that
    /// very pipe and hears his answer. Run with --ignored and MONTANA_LIVE=1.
    #[test]
    #[ignore]
    fn a_copy_gives_a_fresh_machine_the_pipe_and_the_letters_back() {
        let root = std::env::temp_dir().join(format!("montana-history-live-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let (va, wa, ta) = person(&root, "alice");
        let (vb, wb, tb) = person(&root, "bob");
        let (ba, bb) = (Book::new(va.clone()), Book::new(vb.clone()));
        let (sa, sb) = (media::Store::at(&root.join("alice-media")).unwrap(), media::Store::at(&root.join("bob-media")).unwrap());
        let (pa, pb) = (crate::presence::Presence::default(), crate::presence::Presence::default());
        let arc = crate::history::Archive::new(&root.join("alice-archive"), crate::history::keys(&wa).unwrap(), [1; 16]);
        let alice = Desk { vault: &va, book: &ba, twin: ta.clone(), author_key: seed::author_key_of(&wa), my_name: "Alice".into(), news: Default::default(),
                           media: &sa, faces: &sa, self_face: vec![], about: Default::default(), read_receipts: true, presence: &pa, archive: Some(arc.clone()) };
        let bob = Desk { vault: &vb, book: &bb, twin: tb, author_key: seed::author_key_of(&wb), my_name: "Bob".into(), news: Default::default(),
                         media: &sb, faces: &sb, self_face: vec![], about: Default::default(), read_receipts: true, presence: &pb, archive: None };
        let wait = |who: &Desk, ok: &dyn Fn() -> bool| {
            for _ in 0..20 {
                who.fetch_once();
                if ok() {
                    return true;
                }
                std::thread::sleep(std::time::Duration::from_secs(2));
            }
            false
        };
        let link = (Card { vault: &va }).offer_permanent("Alice").unwrap();
        let mut met = meeting::Outcome::Refused;
        for _ in 0..10 {
            met = meeting::meet(&vb, &bb, &link);
            if matches!(met, meeting::Outcome::Opened(_)) { break; }
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
        let meeting::Outcome::Opened(rb) = met else { panic!("no meeting: {met:?}") };
        bob.send(&rb, "Привет из прошлого");
        assert!(wait(&alice, &|| ba.all().iter().any(|c| !c.msgs.is_empty())), "Alice never heard Bob");
        let ra = ba.all()[0].reference.clone();
        alice.send(&ra, "Ответ из прошлого");
        assert!(wait(&bob, &|| bb.chat(&rb).unwrap().msgs.iter().any(|m| m.text == "Ответ из прошлого")));

        // the copy, and a fresh machine of the same words
        let file = crate::history::make_copy(&arc, &ba, &sa, None).unwrap();
        let (vn, sn) = (Vault::at(&root.join("alice-new")).unwrap(), media::Store::at(&root.join("alice-new-media")).unwrap());
        let bn = Book::new(vn.clone());
        let arc_n = crate::history::Archive::new(&root.join("alice-new-archive"), crate::history::keys(&wa).unwrap(), [2; 16]);
        let records = crate::history::read_copy(&crate::history::keys(&wa).unwrap().entropy, &file).unwrap();
        let back = crate::history::restore(&arc_n, &bn, &sn, None, &records);
        assert_eq!((back.chats, back.records), (1, 2), "the pipe and both letters came back");
        let c = bn.chat(&ra).unwrap();
        assert_eq!(c.name, "Bob");
        assert!(c.msgs.iter().any(|m| !m.mine && m.text == "Привет из прошлого") && c.msgs.iter().any(|m| m.mine && m.text == "Ответ из прошлого"));
        let pn = crate::presence::Presence::default();
        let alice_new = Desk { vault: &vn, book: &bn, twin: ta, author_key: seed::author_key_of(&wa), my_name: "Alice".into(), news: Default::default(),
                               media: &sn, faces: &sn, self_face: vec![], about: Default::default(), read_receipts: true, presence: &pn, archive: Some(arc_n) };
        alice_new.send(&ra, "Пишу с новой машины");
        assert!(wait(&bob, &|| bb.chat(&rb).unwrap().msgs.iter().any(|m| m.text == "Пишу с новой машины")), "Bob never heard the fresh machine");
        bob.send(&rb, "Слышу тебя");
        assert!(wait(&alice_new, &|| bn.chat(&ra).unwrap().msgs.iter().any(|m| m.text == "Слышу тебя")), "the fresh machine never heard Bob");

        // the light copy: Alice's machine lays it on the nodes; a third machine of her words takes it back by the words alone
        assert!(crate::history::lay_light(&wa, &arc, 1, crate::history::card_record(&[("userName", "Alice".into())])), "the light copy did not reach the nodes");
        let copies = crate::history::take_light(&wa, &alice.twin, &crate::history::keys(&wa).unwrap().entropy);
        assert!(!copies.is_empty(), "no light copy came back");
        let (v3, s3) = (Vault::at(&root.join("alice-third")).unwrap(), media::Store::at(&root.join("alice-third-media")).unwrap());
        let b3 = Book::new(v3);
        let arc3 = crate::history::Archive::new(&root.join("alice-third-archive"), crate::history::keys(&wa).unwrap(), [3; 16]);
        let back3 = crate::history::restore(&arc3, &b3, &s3, None, &copies[0]);
        assert_eq!(back3.chats, 1, "the light copy gave the pipe back");
        assert_eq!(crate::history::card_words(&copies[0]), vec![("userName", "Alice".to_string())], "and the person's name");
        assert!(b3.chat(&ra).unwrap().msgs.iter().any(|m| m.text == "Привет из прошлого"));
        let _ = std::fs::remove_dir_all(&root);
    }
}
