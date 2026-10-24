import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { t, locale } from "./strings.js";
import { keptPictures } from "./caches.js";
import { Glyph } from "./TopBar.jsx";
import logo from "./assets/logo.png";
import symbolOfTime from "./assets/symbol_of_time.jpg";
import { GroupFace } from "./Groups.jsx";
import { parseLetter as chessLetter } from "./chess-core.js";

/** The book's word to the window (lib.rs CHANGED): something moved, ask again. */
export function useChanged(fn) {
  const ref = useRef(fn);
  ref.current = fn;
  useEffect(() => {
    let stop = null, gone = false;
    listen("montana://changed", () => ref.current()).then((u) => { if (gone) u(); else stop = u; });
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

/** The name a chat shows: theirs, or «Correspondent» (iOS MTNameBook.display). */
export const chatName = (name) => (name && name.trim()) || t("Correspondent");
/** SAVED MESSAGES (iOS savedMessagesKey): the room of writing to oneself -- its key English, its title the language's own word */
export const SAVED = "Saved Messages";
export const rowTitle = (ref, name) => (ref === SAVED ? t("Saved Messages") : chatName(name));

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
export function QRCard({ person, onScan }) {
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
      <div className="qr-title">{t("No chats yet")}</div>
      <div className="code-view">
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
        {card && <div className="card-link" title={card.link}>{card.link}</div>}
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
export function ChatRow({ row, active, onOpen, onMenu, me }) {
  const saved = row.ref === SAVED;   // one's own face, no delivery dots (iOS rowStatus: nil in a room without a wire)
  // A DRAFT STANDS UNDER THE NAME (iOS ChatRow, the author's word 20.09): «Draft:» red and the words grey in place of the last
  // letter -- every chat's but the one open beside the list, whose words the list learns when it is left. Otherwise the letter's
  // own words, no speaker before them; an emptied chat says nothing (iOS ChatStore.listPreview / rowPreview)
  const draft = row.draft && !active ? row.draft.replace(/\s+/g, " ") : "";
  const words = draft ? "" : row.at ? (row.secret ? "🔑 " + t("Shared password") : row.hidden ? t("Hidden by the filter") : letterPreview(row.last)) : "";
  return (
    <div className={"row" + (active ? " active" : "")} role="button" tabIndex={0} onClick={onOpen} aria-label={rowTitle(row.ref, row.name)}
         aria-description={draft ? t("Draft:") + " " + draft : words}
         onContextMenu={(e) => { e.preventDefault(); onMenu?.(e); }}
         onKeyDown={(e) => e.key === "Enter" && onOpen()} data-ref={row.ref}>
      {saved ? <SelfFace name={me?.name} version={me?.face} size={48} />
        : row.group ? <GroupFace size={48} chat={row.ref} version={row.face} /> : <Face chat={row.ref} version={row.face} size={48} live={row.live} />}
      <div className="words">
        <div className="top">
          <span className="name">{rowTitle(row.ref, row.name)}</span>
          {row.muted && <Glyph name="bellSlash" size={12} color="var(--gray)" />}
          {row.mine && row.at > 0 && !saved && (row.state === -1 ? <FailedMark /> : <Dots rung={row.state} />)}
          <span className="time">{rowTime(row.at)}{row.blocked && <span className="nosign"><Glyph name="nosign" size={11} color="var(--red)" /></span>}</span>
        </div>
        <div className="bottom">
          {draft ? <span className="preview"><span className="draft-word">{t("Draft:")}</span> {draft}</span> : <span className="preview">{words}</span>}
          {row.unread > 0 ? <span className="badge">{row.unread}</span>   /* blue even on a muted chat (iOS ChatRow: Color.blue) */
            : row.marked ? <span className="marked" aria-label={t("Mark as unread")} />
            : row.pinned ? <span className="pinned"><Glyph name="pin" size={12} color="var(--gray)" /></span> : null}
        </div>
      </div>
    </div>
  );
}

/** THE CHAT'S DELETION (iOS swipe «trash» → the sheet): «Permanently delete the chat with %@?» -- for both, or for me only. */
export function EraseSheet({ row, onClose, onErased }) {
  const go = (both) => { invoke("chat_erase", { chat: row.ref, both }); onErased(row.ref); };
  return (
    <div className="sheet-shade" onClick={onClose}>
      <div className="action-sheet" onClick={(e) => e.stopPropagation()} role="alertdialog">
        <div className="action-group">
          <div className="action-title">{t("Permanently delete the chat with %@?", { "%@": chatName(row.name) })}</div>
          <button className="action red" onClick={() => go(true)}>{t("Delete for me and them")}</button>
          <button className="action" onClick={() => go(false)}>{t("Delete for me only")}</button>
        </div>
        <button className="action cancel" onClick={onClose}>{t("Cancel")}</button>
      </div>
    </div>
  );
}

/** The row's menu on a right click (iOS: the swipe's tiles, MontanaChatsList 795-808): pin, sound, archive, unread, delete. */
export function RowMenu({ at, onDelete, onClose, onBlock }) {
  const r = at.row;
  const flag = (f, on) => {
    if (f === "unblock") invoke("chat_block", { chat: r.ref, on: false }); else invoke("chat_flag", { chat: r.ref, flag: f, on });
    onClose();
  };
  const item = (label, icon, f, on) => (
    <button className="menu-row" role="menuitem" onClick={() => flag(f, on)}><span>{label}</span><Glyph name={icon} size={18} /></button>
  );
  return (
    <div className="menu-shade" onClick={onClose} onContextMenu={(e) => { e.preventDefault(); onClose(); }}>
      <div className="letter-menu" style={{ left: Math.min(at.x, window.innerWidth - 250), top: Math.min(at.y, window.innerHeight - 290) }}
           onClick={(e) => e.stopPropagation()} role="menu">
        <div className="menu-rows">
          {!r.archived && (r.pinned ? item(t("Unpin"), "pinSlash", "pin", false) : item(t("Pin"), "pin", "pin", true))}
          {r.muted ? item(t("Unmute"), "bellFill", "mute", false) : item(t("Mute"), "bellSlash", "mute", true)}
          {r.archived ? item(t("Unarchive"), "unarchive", "archive", false) : item(t("Archive"), "archive", "archive", true)}
          {r.unread > 0 || r.marked ? item(t("Mark as read"), "markRead", "unread", false) : item(t("Mark as unread"), "circle", "unread", true)}
          {/* Saved Messages is neither blocked nor deleted (iOS: ChatStore.deleteChat refuses a room without a wire) */}
          {r.ref !== SAVED && (r.blocked ? item(t("Unblock"), "nosign", "unblock", false)
            : <button className="menu-row red" role="menuitem" onClick={() => { onClose(); onBlock(r); }}><span>{t("Block")}</span><Glyph name="nosign" size={18} /></button>)}
          {r.ref !== SAVED && <button className="menu-row red" role="menuitem" onClick={onDelete}><span>{t("Delete chat")}</span><Glyph name="trash" size={18} /></button>}
        </div>
      </div>
    </div>
  );
}

/** THE ARCHIVE'S ROW (iOS: pulled down over the list): the box, «Archive», how many are in it. */
export function ArchiveRow({ count, onOpen }) {
  return (
    <div className="row" role="button" tabIndex={0} onClick={onOpen} aria-label={t("Archive")} onKeyDown={(e) => e.key === "Enter" && onOpen()}>
      <div className="face archive-face"><Glyph name="archive" size={22} color="#fff" /></div>
      <div className="words">
        <div className="top"><span className="name">{t("Archive")}</span></div>
        <div className="bottom"><span className="preview">{count}</span></div>
      </div>
    </div>
  );
}
