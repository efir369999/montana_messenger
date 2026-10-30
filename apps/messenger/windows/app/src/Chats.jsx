import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { t, locale } from "./strings.js";
import { keptPictures } from "./caches.js";
import { Glyph } from "./TopBar.jsx";
import logo from "./assets/logo.png";
import symbolOfTime from "./assets/symbol_of_time.jpg";
import glassPreview from "./assets/glass_preview_dark.png";
import { GroupFace } from "./Groups.jsx";
import { parseLetter as chessLetter } from "./chess-core.js";
import { spring, turnEdge } from "./turn.js";
import { endFoldedCall, unfoldCall, useFoldedCall } from "./Call.jsx";
import { RoomRowMark } from "./Room.jsx";

/** How long a read the book's word asked for may stay unanswered before the next word asks again all the same. */
const CHANGED_HOLD_MS = 10000;

/** The book's word to the window (lib.rs CHANGED): something moved, ask again. ONE READ IN FLIGHT, ONE MORE AFTER IT (the freeze's
 *  P2.11, 25.10.2026): the channel's landing says «changed» once a letter (lib.rs land), and every read it asks for is its own task
 *  of the blocking pool -- a backlog of letters would start hundreds of copies of the book and unseals at once. While the read a word
 *  asked for is on its way (what `fn` returns: its promise), the words that follow ask for one read more, made after it answers,
 *  with what the page is then; the word carries nothing, so nothing is lost. A read that never answers holds the next word back
 *  no longer than CHANGED_HOLD_MS. */
export function useChanged(fn) {
  const ref = useRef(fn);
  ref.current = fn;
  useEffect(() => {
    let stop = null, gone = false, busy = false, again = false;
    const run = () => {
      if (gone) return;
      if (busy) { again = true; return; }
      busy = true;
      again = false;
      let held = 0;
      const read = Promise.resolve().then(() => ref.current()).catch(() => {});
      Promise.race([read, new Promise((ok) => { held = setTimeout(ok, CHANGED_HOLD_MS); })]).then(() => {
        clearTimeout(held);
        busy = false;
        if (again) run();
      });
    };
    listen("montana://changed", run).then((u) => { if (gone) u(); else stop = u; });
    return () => { gone = true; stop && stop(); };
  }, []);
}

const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

/** The hour as the platform writes it (DateFormatter timeStyle .short). */
export const hourOf = (at) => new Date(at).toLocaleTimeString(locale, { hour: "numeric", minute: "2-digit" });

/** The row's moment (iOS MTClock.listStamp): today the hour; the six days before, the weekday («Пн»); older, the day and the
 *  month («19.10»). No «Yesterday» in the list. */
export function rowTime(at) {
  if (!at) return "";
  const d = new Date(at), today = startOfDay(new Date());
  if (at >= today) return hourOf(at);
  if (at >= today - 6 * 86400000) {
    const w = d.toLocaleDateString(locale, { weekday: "short" }).replace(".", "");
    return w.charAt(0).toUpperCase() + w.slice(1);
  }
  return d.toLocaleDateString(locale, { day: "2-digit", month: "2-digit" });
}

const STICKER = "\u2063\u2063", MEDIA = "\u200B\u200BMD:", VOICE = "\u200B\u200BVC:";
/** THE MONEY FLOW BEGAN IN THIS CHAT (iOS MTMoneyFlowRow): this machine's own row, never on the wire. */
export const FLOW_ROW = "\u200B\u200BMF:";

/** What a letter is: words, a sticker (a large emoji), or a picture, a film, a voice, a file. */
export function letterKind(text) {
  if (text.startsWith(STICKER)) return "sticker";
  if (text.startsWith(MEDIA) || text.startsWith(VOICE)) return "media";
  return "text";
}

/** The words a letter shows in the list and in a quote (iOS ChatStore.listPreview): a picture as «📷 Photo», a sticker as its
 *  emoji, words as they are. */
export function letterPreview(text) {
  if (chessLetter(text)) return "♟ " + t("Chess");   // a game's letter says what it is (iOS MTRowLetter.preview)
  if (text === FLOW_ROW) return "🪙 " + t("Money flow has begun");
  const kind = letterKind(text);
  if (kind === "sticker") return text.slice(2);
  if (kind === "text") return text;
  if (text.startsWith(VOICE)) return t("Voice message");
  let o = {};
  try { o = JSON.parse(text.slice(MEDIA.length)); } catch { /* the plate says «Media» */ }
  if (o.cap) return o.cap;
  if (o.k === "img" && o.n === "montana-card") return t("Sticker");   // a sticker of a set rides the picture road under the card's name (iOS)
  if (o.k === "img") return "📷 " + t("Photo");
  if (o.k === "vid") return o.r ? t("Video message") : t("Video");
  if (o.k === "aud") return t("Voice message");
  if (o.k === "doc" && /^stick_.+\.gif$/i.test(o.n || "")) return t("Sticker");
  if (o.k === "doc" && /^gif_.+\.gif$/i.test(o.n || "")) return "GIF";
  if (o.k === "doc") return o.n === "montana-card" ? t("Sticker") : (o.n || t("File"));
  return t("Media");
}

/** THE WORDS OF THE LAST LETTER IN THE LIST (iOS ChatStore.listPreview, MTRowLetter.preview / mediaWords): a call as its handset or
 *  camera and what became of it, a coin letter as its coins, a picture, a film, a voice, a file in the vocabulary the banner and the
 *  reply plate share, a sealed long letter as «New message». The row's own (the words a quote carries on the wire stay letterPreview). */
const CALL_ROW = "\u200B\u200BCL:", MISSED_ROW = "\u200B\u200BMC:", LONG_ROW = "\u2063LB:";
const coinCount = (text) => {
  if (!text.startsWith("🪙 ") || text.length > 512) return null;
  const parts = text.split("\n");
  if (parts.length !== 2 || !parts[1].startsWith("montana://coin/1/")) return null;
  const n = parseInt(parts[0].slice(2).trim(), 10);
  return n > 0 ? n : null;
};
const manifestOf = (text) => { try { return JSON.parse(text.slice(MEDIA.length)); } catch { return null; } };
export function listPreview(text) {
  if (text.startsWith(CALL_ROW)) {
    let o = {};
    try { o = JSON.parse(text.slice(CALL_ROW.length)); } catch { /* a voice call by default */ }
    const icon = o.v ? "📹" : "📞";
    if (o.miss) return `${icon} ${t(o.inc ? "Missed call" : "Unanswered call")}`;
    return `${icon} ${t(o.v ? "Video call" : "Voice call")}`;
  }
  if (text.startsWith(MISSED_ROW)) return "📞 " + t("Missed call");
  if (chessLetter(text)) return "♟ " + t("Chess");
  if (text === FLOW_ROW) return "🪙 " + t("Money flow has begun");
  const coins = coinCount(text);
  if (coins) return `🪙 ${coins} ${t("coins")}`;
  if (text.startsWith(VOICE)) return "🎤 " + t("Voice message");
  if (text.startsWith(MEDIA)) {
    const o = manifestOf(text);
    if (!o) return t("Media");
    const cap = (o.cap || "").trim();
    if ((o.k === "img" || o.k === "doc") && o.n === "montana-card") return t("Sticker");   // a sticker of a set rides under the card's name
    if (o.k === "doc" && /^stick_.+\.gif$/i.test(o.n || "")) return t("Sticker");
    if (o.k === "doc" && (/^gif_.+\.gif$/i.test(o.n || "") || /\.gif$/i.test(o.n || ""))) return "GIF";
    if (o.k === "img") return "📷 " + (cap || t("Photo"));
    if (o.k === "vid") return o.r ? "📹 " + t("Video message") : "📹 " + (cap || t("Video"));
    if (o.k === "aud") return "🎤 " + t("Voice message");
    if (o.k === "doc") return "📄 " + (o.n || t("File"));
    return t("Media");
  }
  if (text.startsWith(LONG_ROW)) return t("New message");
  if (letterKind(text) === "sticker") return text.slice(2);
  return text || t("New message");
}
const AUDIO_NAME = /\.(mp3|m4a|aac|wav|flac|ogg|opus|aiff?|alac|wma)$/i;
/** WHAT THE ROW'S THUMBNAIL STANDS FOR (iOS ChatStore.rowMediaKind): a call's handset or camera, a voice, a round note, a film, a
 *  picture, a song, a file, a web link; null -- none. */
export function rowMediaKind(text) {
  if (text.startsWith(CALL_ROW)) {
    let o = {};
    try { o = JSON.parse(text.slice(CALL_ROW.length)); } catch { /* a voice call */ }
    return o.v ? "vcall" : "acall";
  }
  if (text.startsWith(VOICE)) return "aud";
  if (text.startsWith(MEDIA)) {
    const o = manifestOf(text) || {};
    if (o.k === "aud") return "aud";
    if (o.k === "vid") return o.r ? "vnote" : "vid";
    if (o.k === "img") return "img";
    if (o.k === "doc") return AUDIO_NAME.test(o.n || "") ? "music" : "doc";
    return null;
  }
  if (letterKind(text) === "text" && !text.startsWith("\u200B") && /https?:\/\/\S/i.test(text)) return "link";
  return null;
}
/** The row's words without the glyph the vocabulary puts first, when a thumbnail stands there (iOS MontanaRowWords.bare). */
const bare = (p) => { for (const g of ["🎤 ", "📹 ", "📷 ", "📄 ", "📞 "]) if (p.startsWith(g)) return p.slice(g.length); return p; };

/** ONE THUMBNAIL OF WHAT A LETTER CARRIES (iOS MTLetterThumb, side 20): the voice's round of glass with its play, the round note's
 *  window with its poster, the photo's or the film's poster -- else a quiet plate (white 0.16, corners 0.22 of the side) with the
 *  glyph at half the side in the secondary grey: the play for music, the handset and the camera for the calls, the link, the file. */
export function RowThumb({ kind, text, side = 20 }) {
  const o = text.startsWith(MEDIA) ? manifestOf(text) || {} : {};
  const poster = o.th ? `data:image/jpeg;base64,${o.th}` : null;
  if (kind === "aud") {
    return <span className="row-thumb voice-round" style={{ width: side, height: side }}><Glyph name="playFill" size={side * 0.4} color="#fff" /></span>;
  }
  if (kind === "vnote") {
    return <span className="row-thumb note-round" style={{ width: side, height: side }}>{poster && <img src={poster} alt="" />}</span>;
  }
  if ((kind === "img" || kind === "vid") && poster) {
    return <span className="row-thumb poster" style={{ width: side, height: side, borderRadius: side * 0.22 }}><img src={poster} alt="" /></span>;
  }
  const glyph = { img: "photo", vid: "video", music: "playFill", acall: "phone", vcall: "video", link: "link" }[kind] || "doc";
  return <span className="row-thumb plate" style={{ width: side, height: side, borderRadius: side * 0.22 }}><Glyph name={glyph} size={side * 0.5} color="var(--gray)" /></span>;
}

/** The name a chat shows: theirs, or «Correspondent» (iOS MTNameBook.display). */
export const chatName = (name) => (name && name.trim()) || t("Correspondent");
/** SAVED MESSAGES (iOS savedMessagesKey): the room of writing to oneself -- its key English, its title the language's own word */
export const SAVED = "Saved Messages";
export const rowTitle = (ref, name) => (ref === SAVED ? t("Saved Messages") : ref === BOT ? BOT_NAME : chatName(name));
/** OUR BOT (iOS MTBot, MTChatFolders.swift 188-206): Montana's bot where it lives -- a row of All and of the Bots folder, its face
 *  Montana's glass icon (montanaRoomFace «IconGlassPreview»), «bot» under its name; a tap opens it there, and it keeps no
 *  conversation on this computer. */
export const BOT = "bot:MTBusiness_bot";
const BOT_NAME = "MTBusiness_bot";
export const BOT_LINK = "https://t.me/MTBusiness_bot";
export const BOT_ROW = { ref: BOT, name: BOT_NAME, last: "", at: 0, mine: false, state: 0, unread: 0, face: 0, pinned: false, archived: false,
                         muted: false, marked: false, live: false, blocked: false, group: false, kind: "", draft: "" };
/** The bot's face: the app's glass icon in the face's circle with its rim (MTChatFace face: montanaRoomFace). */
export function BotFace({ size = 48 }) {
  return <div className="face" style={{ width: size, height: size }}><img src={glassPreview} alt="" className="face-photo" /></div>;
}

/** The faces as addresses the window can draw: fetched once per version and kept while the window lives. */
const faceUrls = keptPictures(new Map());
export function useFace(chat, version) {
  const key = `${chat}:${version}`;
  const [url, setUrl] = useState(faceUrls.get(key) || null);
  useEffect(() => {
    if (!version) { setUrl(null); return; }
    if (faceUrls.has(key)) { setUrl(faceUrls.get(key)); return; }
    let live = true;
    invoke("face_get", { chat }).then((buf) => {
      const u = URL.createObjectURL(new Blob([buf], { type: "image/jpeg" }));
      faceUrls.set(key, u);
      if (live) setUrl(u);
    }).catch(() => live && setUrl(null));
    return () => { live = false; };
  }, [key]);
  return url;
}

/** A FACE (iOS AvatarCircle): their photo; without one the time mark -- the gold Logo at 28% of the side on black, a 35%
 *  white rim (MTTimeMarkAvatar). */
export function Face({ chat, version, size = 48, live }) {
  const url = useFace(chat, version);
  return (
    <div className="face-wrap" style={{ width: size, height: size }}>
      <div className="face" style={{ width: size, height: size }}>
        {url ? <img src={url} alt="" className="face-photo" />
          : <img src={logo} alt="" style={{ width: size * 0.28, height: size * 0.28 }} />}
      </div>
      {live && <span className="live-dot" />}
      {chat && !chat.startsWith("grp:") && <Badges who={chat} size={size} />}
    </div>
  );
}

/** THE BADGES OF A FACE (iOS MTAvatarBadgePair): the balance on the left in its short form, the Global Level on the right in the
 *  colour of its rank in the public distribution (red at the lowest reported level, green at the highest, grey before it is read);
 *  on a face of 28 and more. One reading every five seconds is shared by every face. */
let badgeBook = { mine: {}, told: {} }, badgeAt = 0, badgeAsk = null;
function useBadges() {
  const [b, setB] = useState(badgeBook);
  useEffect(() => {
    let live = true;
    const read = () => {
      if (Date.now() - badgeAt < 5000) { setB(badgeBook); return; }
      badgeAt = Date.now();
      badgeAsk = badgeAsk || invoke("coin_badges").then((x) => { badgeBook = x; return x; }).catch(() => badgeBook).finally(() => { badgeAsk = null; });
      badgeAsk.then((x) => live && setB(x));
    };
    read();
    const id = setInterval(read, 5000);
    return () => { live = false; clearInterval(id); };
  }, []);
  return b;
}
const shortCoins = (n) => new Intl.NumberFormat(locale, { notation: "compact", maximumFractionDigits: 1 }).format(Math.max(0, n));
export function Badges({ who, size }) {
  const b = useBadges();
  if (size < 28) return null;
  const x = who === "@me" ? b.mine : b.told?.[who];
  if (!x || (x.coins == null && x.level == null)) return null;
  const type = Math.min(13, Math.max(9, size * 0.18)), height = type * 1.6;
  const colour = x.rank == null ? "hsl(0 0% 35%)" : `hsl(${Math.round(x.rank * 120)} 82% 42%)`;
  const spoken = [x.coins != null && t("Balance %@").replace("%@", x.coins), x.level != null && t("Global level %lld").replace("%lld", x.level)].filter(Boolean).join(", ");
  return (
    <div className="face-badges" style={{ fontSize: type, height, top: -height / 2, minWidth: size }} role="img" aria-label={spoken}>
      {x.coins != null && <span className="face-coins" style={{ height }}>{shortCoins(x.coins)}</span>}
      <span className="grow" />
      {x.level != null && <span className="face-level" style={{ height, minWidth: height, background: colour }}>{x.level}</span>}
    </div>
  );
}

/** THE PRESENCE LINE (iOS ChatStore.presenceWord, MontanaSeen): the live word in green -- typing, watching, in chat, online --
 *  else when they were last seen, in red: minutes within the hour, «Today»/«Yesterday» with the hour, else the date; when
 *  they hide it, or I do, only the coarse classes. [text, live] or null. */
export function seenText(s, exact) {
  if (!s) return null;
  const live = { typing: "typing…", watching: "watching", inchat: "in chat", online: "online" }[s.state];
  if (live) return [t(live), true];
  if (s.state === "gone") return [t("seen long ago"), false];
  if (s.state !== "seen" || !s.at) return null;
  const diff = Date.now() - s.at;
  if (s.hides || !exact) {
    const d = diff / 86400000;
    return [t(d < 3 ? "seen recently" : d < 7 ? "seen this week" : d < 30 ? "seen this month" : "seen long ago"), false];
  }
  if (diff < 3600000) return [`${Math.max(1, Math.floor(diff / 60000))} ${t("min")}`, false];
  const day = (x) => new Date(new Date(x).getFullYear(), new Date(x).getMonth(), new Date(x).getDate()).getTime();
  const today = day(Date.now());
  if (day(s.at) === today) return [t("today at %@", { "%@": hourOf(s.at) }), false];
  if (day(s.at) === today - 86400000) return [t("yesterday at %@", { "%@": hourOf(s.at) }), false];
  return [new Date(s.at).toLocaleDateString(locale, { day: "2-digit", month: "2-digit", year: "numeric" }), false];
}

/** THE OWN FACE (iOS MTSelfFace): my photo, or a black circle with my initial, bold, at 40% of the side. */
export function SelfFace({ name, version, size = 84, onClick }) {
  const url = useFace("", version);
  const ch = Array.from((name || "").trim())[0] || "";
  const emoji = /\p{Extended_Pictographic}/u.test(ch);
  return (
    <div className={"self-face" + (onClick ? " pressable" : "")} onClick={onClick}
         style={{ width: size, height: size, fontSize: size * (emoji ? 0.62 : 0.4), position: "relative", overflow: "visible" }}>
      {url ? <img src={url} alt="" className="face-photo" /> : ch.toUpperCase()}
      <Badges who="@me" size={size} />
    </div>
  );
}

/** THE THREE DOTS (iOS MTDeliveryDots): 5 points, 5 apart; green once their rung is reached, white 0.30 before. */
export function Dots({ rung }) {
  return (
    <span className="dots">
      {[1, 2, 3].map((k) => <i key={k} className={rung >= k ? "on" : ""} />)}
    </span>
  );
}

/** THE RED MARK of a letter that did not go (iOS MTFailedMark: exclamationmark.circle.fill). */
export const FailedMark = () => <span className="failed-mark" aria-label={t("Not sent")}>!</span>;

export function ladderWord(state) {
  return state === -1 ? t("Not sent") : [t("Sending…"), t("Sent"), t("Delivered"), t("Read")][Math.max(0, Math.min(3, state))];
}

/** THE CARD ON THE EMPTY LIST (iOS MontanaQRCard + MontanaCodeView, ContentView.swift 4343-4658). */
export function QRCard({ person, onScan, onExpand, titled = true }) {
  const [card, setCard] = useState(null);
  const [copied, setCopied] = useState(false);
  const [shared, setShared] = useState(false);
  const pick = (kind) => invoke("card", { kind }).then(setCard);
  useEffect(() => { invoke("card", { kind: null }).then(setCard); }, []);
  useEffect(() => {   // the link of the day renews exactly a day after its birth: the card redraws (iOS .montanaCardSpent)
    if (!card?.renews) return;
    const id = setTimeout(() => invoke("card", { kind: null }).then(setCard), Math.max(1000, card.renews - Date.now() + 500));
    return () => clearTimeout(id);
  }, [card?.renews]);
  const copy = async (then) => {
    if (await invoke("card_copy")) { then(true); setTimeout(() => then(false), 2000); }
  };
  const renews = card?.renews
    ? new Date(card.renews).toLocaleString(locale, { day: "numeric", month: "short", year: "numeric", hour: "numeric", minute: "2-digit" })
    : "";
  return (
    <div className="qr-card">
      {/* «No chats yet» over the card of the empty list alone (iOS MontanaQRCard); the full page wears none (MontanaQRFullView) */}
      {titled && <div className="qr-title">{t("No chats yet")}</div>}
      {/* the card of the empty list is one button: a tap beside its own keys opens the code's full page (iOS MontanaQRCard onExpand) */}
      <div className={"code-view" + (onExpand ? " expands" : "")}
           onClick={onExpand ? (e) => { if (!e.target.closest("button, a, .card-link")) onExpand(); } : undefined}>
        <SelfFace name={person.name} version={person.face} />
        <div className="caption">{t("This code opens one correspondence with you and nothing else.")}</div>
        <div className="qr-tile">
          {card ? (
            <svg className="qr" viewBox={`0 0 ${card.size} ${card.size}`} shapeRendering="crispEdges" role="img" aria-label="QR">
              <path d={card.path} fill="#000" />
            </svg>
          ) : <div className="qr qr-pending"><span className="spinner" /></div>}
          <div className="qr-logo"><img src={symbolOfTime} alt="" /></div>
        </div>
        <div className="segmented" role="tablist">
          {[["permanent", t("Permanent")], ["temporary", t("Temporary")]].map(([k, label]) => (
            <button key={k} role="tab" aria-selected={card?.kind === k} className={card?.kind === k ? "on" : ""}
                    onClick={() => card?.kind !== k && pick(k)}>{label}</button>
          ))}
        </div>
        <div className="caption">
          {card?.kind === "temporary" ? t("The link renews on %@", { "%@": renews })
            : t("The link does not expire: whoever holds it can always write to you.")}
        </div>
        {/* the link under the code is a link: a tap opens it, a drag selects it (iOS linkify, textSelection) */}
        {card && <a className="card-link" href={card.link} title={card.link}
                    onClick={(e) => { e.preventDefault(); invoke("open_link", { url: card.link }).catch(() => {}); }}>{card.link}</a>}
        <button className={"copy-link" + (copied ? " done" : "")} onClick={() => copy(setCopied)}>
          <Glyph name={copied ? "tick" : "link"} size={14} />{copied ? t("Link copied") : t("Copy Link")}
        </button>
        <div className="card-doors">
          <button className="card-door share" onClick={async () => {
            // the system's share sheet, as iOS's; the link is copied when the sheet will not open
            const shown = card ? await invoke("share_text", { title: "Montana", text: card.link, link: card.link }).catch(() => false) : false;
            if (!shown) copy(setShared);
          }}>
            <Glyph name={shared ? "tick" : "share"} size={16} />{shared ? t("Link copied") : t("Share")}
          </button>
          <button className="card-door scan" onClick={onScan}><Glyph name="qrScan" size={16} />{t("Scan")}</button>
        </div>
      </div>
    </div>
  );
}

/** THE SCAN, ON WINDOWS (iOS ScanMeetingView points the camera at a code; a desktop has no phone camera to point, and its
 *  links arrive on the clipboard): the link is pasted, and the same meeting runs behind it (MontanaMeeting). The outcomes
 *  are iOS's own alerts. */
export function MeetSheet({ onClose, onOpened }) {
  const [link, setLink] = useState("");
  const [busy, setBusy] = useState(false);
  const [alert, setAlert] = useState(null);
  const field = useRef(null);
  useEffect(() => { field.current?.focus(); }, []);
  const go = async () => {
    if (!link.trim() || busy) return;
    setBusy(true);
    const out = await invoke("meet", { link }).catch(() => ({ kind: "Refused" }));
    setBusy(false);
    if (out.kind === "Opened") return setTimeout(() => onOpened(out.chat), 350);   // the chat opens after the sheet goes (iOS ~0.35 s)
    setAlert(out.kind === "Spent" ? t("Invitation expired. Ask for a new code.")
      : out.kind === "Foreign" ? t("This link is not a Montana invitation.")
      : out.kind === "Own" ? t("This is your own link.")
      : t("The invitation could not be opened. Check the link or try again."));
  };
  return (
    <div className="sheet-shade" onClick={onClose}>
      <div className="meet" onClick={(e) => e.stopPropagation()} role="dialog" aria-label={t("Scan code")}>
        <div className="meet-bar">
          <button className="meet-close" onClick={onClose} aria-label={t("Cancel")}><Glyph name="close" size={18} /></button>
          <div className="meet-title">{t("Scan code")}</div>
        </div>
        <input ref={field} className="meet-field" placeholder="https://montana.quest/perp/…" value={link} aria-label={t("Link")}
               onChange={(e) => setLink(e.target.value)} onKeyDown={(e) => e.key === "Enter" && go()} />
        <div className="meet-hint">{t("Paste the link of a Montana card")}</div>
        <button className="card-door share meet-go" disabled={!link.trim() || busy} onClick={go}>
          {busy ? <span className="spinner dark" /> : t("Open")}
        </button>
      </div>
      {alert && (
        <div className="alert-shade" onClick={(e) => e.stopPropagation()}>
          <div className="alert" role="alertdialog">
            <div className="alert-title">{alert}</div>
            <button onClick={() => setAlert(null)}>{t("OK")}</button>
          </div>
        </div>
      )}
    </div>
  );
}

/** One row of the list (iOS ChatRow in MTLibraryRow, MontanaChatsList.swift 2136-2303): 72 high, the 48 face, 16 to the
 *  words; the name 17 semibold, my last letter's dots and the time 14 gray on the first line; the preview 16 gray and the
 *  blue unread capsule on the second. */
/** THE TWO HANDSETS BESIDE A NAME (iOS CallInlineHandset, MontanaCall.swift 6902-6946): while a call with this person stands folded,
 *  the green (phone.fill) left of the name returns to it, the red (phone.down.fill) right of it ends it -- asking first, «End the
 *  call?» -- each a circle of 26 with the glyph 12 bold white, inside the finger's 44. */
function Handset({ green }) {
  const [asking, setAsking] = useState(false);
  return (
    <>
      <button className={"handset " + (green ? "green" : "red")} aria-label={green ? t("Back") : t("End")}
              onClick={(e) => { e.stopPropagation(); if (green) unfoldCall(); else setAsking(true); }}>
        <span className="handset-face"><Glyph name="phone" size={13} color="#fff" /></span>
      </button>
      {asking && (
        <div className="sheet-shade" onClick={(e) => { e.stopPropagation(); setAsking(false); }}>
          <div className="action-sheet" onClick={(e) => e.stopPropagation()} role="alertdialog">
            <div className="action-group">
              <div className="action-title">{t("End the call?")}</div>
              <button className="action red" onClick={() => { setAsking(false); endFoldedCall(); }}>{t("End")}</button>
            </div>
            <button className="action cancel" onClick={() => setAsking(false)}>{t("Cancel")}</button>
          </div>
        </div>
      )}
    </>
  );
}

export function ChatRow({ row, active, onOpen, onMenu, me, selecting = false, chosen = false }) {
  const saved = row.ref === SAVED;
  const folded = useFoldedCall();
  const calling = folded?.chat === row.ref;   // one's own face, no delivery dots (iOS rowStatus: nil in a room without a wire)
  // A DRAFT STANDS UNDER THE NAME (iOS ChatRow, the author's word 20.09): «Draft:» red and the words grey in place of the last
  // letter -- every chat's but the one open beside the list, whose words the list learns when it is left. Otherwise the letter's
  // own words, no speaker before them; an emptied chat says nothing (iOS ChatStore.listPreview / rowPreview)
  const draft = row.draft && !active ? row.draft.replace(/\s+/g, " ") : "";
  const bot = row.ref === BOT;
  // the last row's words (iOS rowPreview → listPreview): a group's event comes worded by the core
  const thumb = !bot && !draft && row.at && !row.secret && !row.hidden && !row.event ? rowMediaKind(row.last) : null;
  const said = bot ? t("bot") : draft ? "" : row.at ? (row.secret ? "🔑 " + t("Shared password") : row.hidden ? t("Hidden by the filter")
    : row.event ? row.last : listPreview(row.last)) : "";
  const words = thumb ? bare(said) : said;
  return (
    <div className={"row" + (active ? " active" : "")} role="button" tabIndex={0} onClick={onOpen} aria-label={rowTitle(row.ref, row.name)}
         aria-description={draft ? t("Draft:") + " " + draft : words} aria-pressed={selecting ? chosen : undefined}
         onContextMenu={(e) => { e.preventDefault(); onMenu?.(e); }}
         onKeyDown={(e) => e.key === "Enter" && onOpen()} data-ref={row.ref}>
      {/* SELECTING (iOS chatRowCell): the circle 22 left of the row, 10 before its face -- the accent's tick when chosen */}
      {selecting && <span className="pick-circle"><Glyph name={chosen ? "checkCircle" : "circle"} size={22} color={chosen ? "var(--blue)" : "var(--gray)"} /></span>}
      {bot ? <BotFace size={48} /> : saved ? <SelfFace name={me?.name} version={me?.face} size={48} />
        : row.group ? <GroupFace size={48} chat={row.ref} version={row.face} /> : <Face chat={row.ref} version={row.face} size={48} live={row.live} />}
      <div className="words">
        <div className="top">
          {calling && <Handset green />}
          <span className="name chat-name">{rowTitle(row.ref, row.name)}</span>
          {row.group && <RoomRowMark chat={row.ref} />}
          {calling && <Handset />}
          {row.muted && <Glyph name="bellSlash" size={12} color="var(--gray)" />}
          {/* the marks stand beside the name, the time at the line's end (iOS: HStack(spacing: 5) … Spacer()) */}
          <span className="grow" />
          {row.mine && row.at > 0 && !saved && (row.state === -1 ? <FailedMark /> : <Dots rung={row.state} />)}
          <span className="time">{rowTime(row.at)}{row.blocked && <span className="nosign"><Glyph name="nosign" size={11} color="var(--red)" /></span>}</span>
        </div>
        <div className="bottom">
          {draft ? <span className="preview"><span className="draft-word">{t("Draft:")}</span> {draft}</span>
            : <>
              {/* THE ANSWER IN THE ROW (iOS ChatRow: reaction): the face of whoever answered (18 -- mine, or the chat's), the answer at 15,
                  then the letter's words */}
              {row.react && (row.react_mine ? <SelfFace name={me?.name} version={me?.face} size={18} />
                : row.group ? <GroupFace size={18} chat={row.ref} version={row.face} /> : <Face chat={row.ref} version={row.face} size={18} />)}
              {row.react && <span className="row-answer">{row.react}</span>}
              {thumb && <RowThumb kind={thumb} text={row.last} />}<span className="preview">{words}</span>
            </>}
          {/* the hand's mark first, then the count, then the pin (iOS ChatRow: forced, unread, pinned) */}
          {row.marked ? <span className="marked" aria-label={t("Mark as unread")} />
            : row.unread > 0 ? <span className="badge">{row.unread}</span>   /* blue even on a muted chat (iOS ChatRow: Color.blue) */
            : row.pinned ? <span className="pinned"><Glyph name="pin" size={12} color="var(--gray)" /></span> : null}
        </div>
      </div>
    </div>
  );
}

/** THE CHAT'S DELETION (iOS MontanaDeleteChatSheet in MontanaFaceSheet, ContentView.swift 4624-4727): the person's face 72, the question
 *  by name at the subheadline, the actions in descending consequence -- «Delete for me and them» while the pair's pipe is held, «Delete
 *  for me only» -- and «Cancel» as its own group; while a coin letter of mine is on its way in the chat the sheet says so in small grey
 *  and offers no deletion. */
export function EraseSheet({ row, me, onClose, onErased }) {
  const [terms, setTerms] = useState(null);   // {both, coins}
  useEffect(() => { invoke("chat_erase_terms", { chat: row.ref }).then(setTerms).catch(() => setTerms({ both: false, coins: false })); }, [row.ref]);
  const go = (both) => { invoke("chat_erase", { chat: row.ref, both }); onErased(row.ref); };
  return (
    <div className="sheet-shade" onClick={onClose}>
      <div className="action-sheet" onClick={(e) => e.stopPropagation()} role="alertdialog" aria-label={t("Permanently delete the chat with %@?", { "%@": rowTitle(row.ref, row.name) })}>
        <div className="action-group">
          <div className="face-sheet-head">
            {row.ref === SAVED ? <SelfFace name={me?.name} version={me?.face} size={72} />
              : row.group ? <GroupFace size={72} chat={row.ref} version={row.face} /> : <Face chat={row.ref} version={row.face} size={72} />}
            <div className="face-sheet-question">{t("Permanently delete the chat with %@?", { "%@": rowTitle(row.ref, row.name) })}</div>
            {terms?.coins && <div className="face-sheet-note">{t("A coin letter in this chat is on its way. The chat can be deleted once it is delivered or its coins come back.")}</div>}
          </div>
          {terms && !terms.coins && terms.both && <button className="action red" onClick={() => go(true)}>{t("Delete for me and them")}</button>}
          {terms && !terms.coins && <button className="action" onClick={() => go(false)}>{t("Delete for me only")}</button>}
        </div>
        <button className="action cancel" onClick={onClose}>{t("Cancel")}</button>
      </div>
    </div>
  );
}

/** THE MENU ABOUT A PERSON (iOS MTPersonMenu, MontanaMessageMenu.swift 575-639; its deeds MontanaChatsList.swift 1205-1222): a hold
 *  on a row -- here the right button or a long touch -- lays the material over the window and the cloud at the row: the person as
 *  the row showed them (the face 44 and the name, on its own plate), 12 below it the deeds on a plate 250 wide -- «Pin» / «Unpin»,
 *  «Mute» / «Unmute», «Select», «Mark as read» / «Mark as unread», «Archive», and «Delete» where the room has a wire; the cloud
 *  rises on a spring (0.32 / 0.68) from 0.94 and leaves in 0.15 s before its deed. Windows keeps «Block» / «Unblock» under them
 *  (tools/blocks.ps1 blocks from here). */
export function PersonMenu({ at, me, onClose, onSelect, onDelete, onBlock }) {
  const r = at.row;
  const [gone, setGone] = useState(false);
  const cloud = useRef(null);
  const [top, setTop] = useState(null);
  // the cloud's place (MTMenuPlace): 12 above the row's top, kept 8 from the window's top and 10 from its bottom
  useLayoutEffect(() => {
    const h = cloud.current?.offsetHeight || 0;
    let y = at.top - 12;
    if (y + h > window.innerHeight - 10) y = window.innerHeight - 10 - h;
    setTop(Math.max(8, y));
  }, []);
  const close = (then) => {
    if (gone) return;
    setGone(true);
    setTimeout(() => { onClose(); then?.(); }, 150);
  };
  const flag = (f, on) => (f === "unblock" ? invoke("chat_block", { chat: r.ref, on: false }) : invoke("chat_flag", { chat: r.ref, flag: f, on }));
  const unread = r.unread > 0 || r.marked;
  const deed = (label, glyph, act, red) => (
    <button className={"menu-row" + (red ? " red" : "")} role="menuitem" onClick={() => close(act)}><span>{label}</span><Glyph name={glyph} size={18} /></button>
  );
  const local = r.ref === SAVED;   // a room without a wire is neither deleted nor blocked (iOS ChatStore.isLocalRoom)
  return (
    <div className="menu-shade person-shade" onClick={() => close()} onContextMenu={(e) => { e.preventDefault(); close(); }}>
      <div ref={cloud} className={"person-menu" + (gone ? " gone" : "")} role="menu" aria-label={rowTitle(r.ref, r.name)}
           style={{ left: at.left + 12, top: top ?? at.top - 12, visibility: top == null ? "hidden" : undefined }}
           onClick={(e) => e.stopPropagation()}>
        <div className="person-face">
          {local ? <SelfFace name={me?.name} version={me?.face} size={44} />
            : r.group ? <GroupFace size={44} chat={r.ref} version={r.face} /> : <Face chat={r.ref} version={r.face} size={44} />}
          <span className="person-name">{rowTitle(r.ref, r.name)}</span>
        </div>
        <div className="menu-rows">
          {r.pinned ? deed(t("Unpin"), "pinSlash", () => flag("pin", false)) : deed(t("Pin"), "pin", () => flag("pin", true))}
          {r.muted ? deed(t("Unmute"), "bell", () => flag("mute", false)) : deed(t("Mute"), "bellSlash", () => flag("mute", true))}
          {deed(t("Select"), "checkCircle", () => onSelect(r))}
          {unread ? deed(t("Mark as read"), "markRead", () => flag("unread", false)) : deed(t("Mark as unread"), "circle", () => flag("unread", true))}
          {deed(t("Archive"), "archive", () => flag("archive", true))}
          {!local && deed(t("Delete"), "trash", () => onDelete(r), true)}
          {!local && (r.blocked ? deed(t("Unblock"), "nosign", () => flag("unblock"))
            : deed(t("Block"), "nosign", () => onBlock(r), true))}
        </div>
      </div>
    </div>
  );
}

/** THE ARCHIVE'S MENU (iOS ArchivedChatsView .contextMenu, MontanaScreens.swift 63-77): the platform's menu at the pointer --
 *  «Unarchive», «Muted», «Mark as read» / «Mark as unread», «Delete». */
export function RowMenu({ at, onDelete, onClose }) {
  const r = at.row;
  const flag = (f, on) => { invoke("chat_flag", { chat: r.ref, flag: f, on }); onClose(); };
  const item = (label, icon, act, red) => (
    <button className={"menu-row" + (red ? " red" : "")} role="menuitem" onClick={act}><span>{label}</span><Glyph name={icon} size={18} /></button>
  );
  return (
    <div className="menu-shade" onClick={onClose} onContextMenu={(e) => { e.preventDefault(); onClose(); }}>
      <div className="letter-menu" style={{ left: Math.min(at.x, window.innerWidth - 250), top: Math.min(at.y, window.innerHeight - 200) }}
           onClick={(e) => e.stopPropagation()} role="menu">
        <div className="menu-rows">
          {item(t("Unarchive"), "unarchive", () => flag("archive", false))}
          {item(t("Muted"), "bellSlash", () => flag("mute", !r.muted))}
          {r.unread > 0 || r.marked ? item(t("Mark as read"), "markRead", () => flag("unread", false)) : item(t("Mark as unread"), "circle", () => flag("unread", true))}
          {r.ref !== SAVED && item(t("Delete"), "trash", onDelete, true)}
        </div>
      </div>
    </div>
  );
}

/** THE ARCHIVE'S ROW (iOS archiveRow, MontanaChatsList.swift 741-761): a full row of its own -- the circle 48 of white 0.15 with
 *  archivebox.fill 20 grey and the 0.45 rim, «Archive» 17 semibold, the count 16 grey under it, the chevron 14 grey at its end. */
export function ArchiveRow({ count, onOpen }) {
  return (
    <div className="row" role="button" tabIndex={0} onClick={onOpen} aria-label={t("Archive")} onKeyDown={(e) => e.key === "Enter" && onOpen()}>
      <div className="face archive-face"><Glyph name="archive" size={20} color="var(--gray)" /></div>
      <div className="words archive-words">
        <span className="name">{t("Archive")}</span>
        <span className="preview">{count}</span>
      </div>
      <Glyph name="chevronRight" size={14} color="var(--gray)" />
    </div>
  );
}

/** A ROW'S SWIPES (iOS: the chats' list draws them as the platform's swipe actions, MontanaChatListContainer.swift 719-736, the tiles
 *  MontanaChatsList.swift 786-805; the archive's own row SwipeChatRow, MontanaChatsList.swift 1936-2004). The row follows the
 *  finger -- the touch, the pen, the mouse's left button -- and uncovers its tiles under it; let go past half the tiles it stays
 *  open on them, else it goes home; a tap on a tile does the deed and closes the row, a tap on the open row closes it. The chats'
 *  list: the stroke begins in the page's edge zones (the centre turns the pages, MTTabPan), the tiles are the platform's -- the
 *  row's height, one glass (white 0.6 at 0.32) under a white glyph -- and a full stroke to the right performs the first (the audio
 *  call). The archive (capsule): the stroke begins anywhere past 14, the tiles are capsules 52 × 46 seven apart in their colour at
 *  0.55 with a 0.9 rim, the row resists 0.3 past them and snaps on a spring (0.3 / 0.78). */
export function Swipe({ leading = [], trailing = [], capsule = false, free = false, side = 0, onSide, enabled = true, tag, children }) {
  const box = useRef(null), slide = useRef(null), drag = useRef(null), anim = useRef(null), x = useRef(0);
  const tileW = capsule ? 52 : 74, gap = capsule ? 7 : 0;
  const width = (n) => (n ? n * tileW + (n + 1) * gap : 0);
  const lw = width(leading.length), tw = width(trailing.length);
  const [shown, setShown] = useState(0);   // which tiles stand uncovered: 1 the leading, -1 the trailing
  const put = (v) => {
    x.current = v;
    if (slide.current) slide.current.style.transform = Math.abs(v) < 0.5 ? "" : `translateX(${v}px)`;
    box.current?.style.setProperty("--sx", `${v}px`);
    const s = v > 1 ? 1 : v < -1 ? -1 : 0;
    setShown((o) => (o === s ? o : s));
  };
  const go = (v) => {
    anim.current?.();
    anim.current = spring(x.current, v, capsule ? { response: 0.3, damping: 0.78 } : { response: 0.35, damping: 1 }, put, () => { anim.current = null; });
  };
  useEffect(() => { if (!drag.current?.live) go(side > 0 ? lw : side < 0 ? -tw : 0); }, [side, lw, tw]);
  useEffect(() => () => anim.current?.(), []);
  const down = (e) => {
    if (!enabled || drag.current || (e.pointerType === "mouse" && e.button !== 0) || e.clientX <= 16) return;
    if (e.target.closest?.(".swipe-tile")) return;
    if (!capsule && !free && side === 0) {
      // the page's centre is the pages' stroke (MTTabPan): a row's swipe begins in the edge zones
      const list = box.current.closest(".list") || box.current;
      const r = list.getBoundingClientRect(), ex = turnEdge(r.width);
      if (e.clientX - r.left >= ex && r.right - e.clientX >= ex) return;
    }
    drag.current = { id: e.pointerId, x0: e.clientX, y0: e.clientY, base: x.current, live: false, w: box.current.offsetWidth };
  };
  const limit = (nx) => {
    if (!trailing.length && nx < 0) return 0;
    if (!leading.length && nx > 0) return 0;
    if (nx < -tw) return -tw + (nx + tw) * 0.3;
    if (capsule && nx > lw) return lw + (nx - lw) * 0.3;
    return nx;
  };
  const move = (e) => {
    const d = drag.current;
    if (!d || e.pointerId !== d.id) return;
    const dx = e.clientX - d.x0, dy = e.clientY - d.y0;
    if (!d.live) {
      const ax = Math.abs(dx), ay = Math.abs(dy), far = Math.hypot(ax, ay);
      if (capsule) {
        if (far < 14) return;
        if (ax <= ay) { drag.current = null; return; }
      } else if (far > 10) {
        if (ax < ay) { drag.current = null; return; }
      } else if (ay > 2 && ay > ax * 2) { drag.current = null; return; }
      else if (!(ax > 2 && ay * 2 < ax)) return;
      d.live = true;
      anim.current?.();
      try { box.current.setPointerCapture(e.pointerId); } catch { /* the row still follows */ }
    }
    e.preventDefault();
    put(limit(d.base + dx));
  };
  const up = (e) => {
    const d = drag.current;
    if (!d || e.pointerId !== d.id) return;
    drag.current = null;
    if (!d.live) return;
    const f = x.current;
    // a full stroke to the right performs the first tile (iOS performsFirstActionWithFullSwipe on the leading side)
    if (!capsule && leading.length && f > d.w * 0.6) { go(0); onSide?.(0); leading[0].act(); return; }
    const next = f < -tw * 0.5 ? -1 : f > lw * 0.5 ? 1 : 0;
    go(next > 0 ? lw : next < 0 ? -tw : 0);
    onSide?.(next);
  };
  // the open row takes a tap for its own closing (iOS: open, taps go to the tiles, not the row)
  const tapClose = (e) => {
    if (side === 0 || e.target.closest?.(".swipe-tile")) return;
    e.stopPropagation();
    e.preventDefault();
    onSide?.(0);
  };
  const tile = (k, i) => (
    <button key={i} className={"swipe-tile" + (capsule ? " capsule" : "") + (k.red ? " red" : "")} aria-label={k.label}
            style={k.color ? { "--tile": k.color } : undefined} onClick={(e) => { e.stopPropagation(); onSide?.(0); k.act(); }}>
      {k.text ? <span className="swipe-word">{k.text}</span> : <Glyph name={k.icon} size={capsule ? 19 : 22} color="#fff" />}
    </button>
  );
  return (
    <div className={"swipe-box" + (capsule ? " capsule" : "")} ref={box} data-swipe={tag} onPointerDown={down} onPointerMove={move} onPointerUp={up}
         onPointerCancel={up} onClickCapture={tapClose}>
      <div className="swipe-tiles lead" inert={shown <= 0 || undefined} aria-hidden={shown <= 0} style={{ opacity: shown > 0 ? 1 : 0 }}>{leading.map(tile)}</div>
      <div className="swipe-tiles trail" inert={shown >= 0 || undefined} aria-hidden={shown >= 0} style={{ opacity: shown < 0 ? 1 : 0 }}>{trailing.map(tile)}</div>
      <div className="swipe-slide" ref={slide}>{children}</div>
    </div>
  );
}
