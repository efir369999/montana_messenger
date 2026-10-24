import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t, locale } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { chatName, Dots, Face, FailedMark, FLOW_ROW, hourOf, ladderWord, letterKind, letterPreview, rowTitle, SAVED, SelfFace, seenText, useChanged } from "./Chats.jsx";
import { AutoReacts, count } from "./Wallet.jsx";
import { Page, Section } from "./Settings.jsx";
import { CARD_MARK } from "./Card.jsx";
import { listen } from "@tauri-apps/api/event";
import sendButton from "./assets/send_button.png";
import voiceKey from "./assets/ios/VoiceRecordButton.png";
import videoKey from "./assets/ios/VideoRecordButton.png";
import { CardFace, cardLines, sendCard } from "./Card.jsx";
import knight from "./assets/ios/Chesswn.png";
import { MintCoin } from "./Coin.jsx";
import { BIG, manifestOf, MediaBody, sendFile, urlOf } from "./Media.jsx";
import PhotoAlbum from "./PhotoAlbum.jsx";
import { NOTE_STEPS, readNoteQuality } from "./Look.jsx";
import { StickerPanel, StickerSheet } from "./Stickers.jsx";
import { ReportPage } from "./Safety.jsx";
import { ChatGround } from "./Ground.jsx";
import { GroupFace, GroupPage, people, refusalWords, tint } from "./Groups.jsx";
import { callTo } from "./Call.jsx";
import { RoomMark, RoomBar, RoomInvite } from "./Room.jsx";
import { ChessBoard, chessSeat } from "./Chess.jsx";
import { current as chessCurrent, finished as chessFinished, parseLetter as chessLetter, replay as chessReplay } from "./chess-core.js";
import { PlayerBar } from "./PlayerBar.jsx";
import * as player from "./player.js";
import { useLeave } from "./leave.js";

const startOfDay = (at) => { const d = new Date(at); return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); };

/** The day's pill (iOS MTDayLabel): «Today», «Yesterday», else the day and the month («19 октября»). */
function dayTitle(at) {
  const today = startOfDay(Date.now()), day = startOfDay(at);
  if (day === today) return t("Today");
  if (day === today - 86400000) return t("Yesterday");
  return new Date(at).toLocaleDateString(locale, { day: "numeric", month: "long" });
}

/** The stickers of iOS (MontanaBubble.swift montanaStickers): a sticker is a letter of its own, drawn large. */
const STICKERS = ["😀", "😂", "🥰", "😎", "😍", "🤩", "😭", "😤", "🤔", "👍", "👎", "🙏", "👏", "🔥", "🎉", "❤️", "💔", "💯", "✅", "🙌", "🤝", "👀",
  "🥳", "😉", "😢", "😱", "🤯", "💪", "🌟", "🤗"];
/** The emoji the panel offers to the words (the person's Windows also has its own panel: Win + .). */
export const EMOJI = ["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃", "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "😚", "😙", "😋", "😛",
  "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔", "🤐", "🤨", "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "🤥", "😌", "😔", "😪", "🤤", "😴",
  "😷", "🤒", "🤕", "🤢", "🤮", "🥵", "🥶", "🥴", "😵", "🤯", "🤠", "🥳", "😎", "🤓", "🧐", "😕", "😟", "🙁", "😮", "😯", "😲", "😳",
  "🥺", "😦", "😧", "😨", "😰", "😥", "😢", "😭", "😱", "😖", "😣", "😞", "😓", "😩", "😫", "🥱", "😤", "😡", "😠", "🤬", "👍", "👎",
  "👌", "🤌", "✌️", "🤞", "🤟", "🤘", "🤙", "👋", "👏", "🙌", "🙏", "🤝", "💪", "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔",
  "💯", "🔥", "✨", "🌟", "⭐", "🎉", "🎁", "✅", "❌", "⚡", "☀️", "🌙", "☕", "🍀", "🌹", "🐶", "🐱", "🦊", "🐻", "🐼"];

/** What a person reaches for first (iOS MTReactions.common). */
export const REACTIONS = ["👍", "❤️", "🔥", "😂", "😮", "😢", "🎉", "🙏", "👏"];
/** π's boxes as the amounts given (iOS MTPiLevels.all: the thirteen boxes, the author's word 03.10 22:02), in their short form. */
const PI_BOXES = Array.from({ length: 19 }, (_, i) => Number("3141592653589793238".slice(0, i + 1)));
const shortBox = (n) => new Intl.NumberFormat(locale, { notation: "compact", maximumFractionDigits: 1 }).format(n);

/** THEIR LIVE WORDS (iOS LiveDraftBubble): what their field holds while both have the chat's Money Flow on -- never a letter,
 *  never in the book; the caret stands where they hold it, the letter they answer over the words. */
function LiveDraft({ text, caret, quote }) {
  const at = caret < 0 || caret > text.length ? text.length : caret;
  if (text.startsWith(CARD_MARK)) {
    // the card being written (iOS MontanaCardPlate in the draft): the gold plate fills in as they type
    return <div className="bubble-row theirs live-draft-row"><div className="live-card"><CardFace lines={text.slice(CARD_MARK.length).split("\n")} width={280} /></div></div>;
  }
  return (
    <div className="bubble-row theirs live-draft-row">
      <div className="bubble live-draft">
        {quote && (
          <span className="quote"><span className="quote-who">{quote.who}</span><span className="quote-words">{quote.words}</span></span>
        )}
        <span className="bubble-text">{text.slice(0, at)}<span className="live-caret">{"│"}</span>{text.slice(at)}</span>
      </div>
    </div>
  );
}

/** THE CONVERSATION (iOS MontanaConversation + MontanaMessageFeed + MontanaBubble): the bar with the face and the name, the
 *  feed of bubbles day by day, my newest letter's ladder under it, the field and the send door. The chat before the person's
 *  eyes says «read», 0.8 s after, while it still is (iOS sendReadMark). A letter's menu (right click, iOS long press):
 *  the answers, Reply, Copy, Edit, Delete. */
/** The words a forwarded letter wears in the quote's place (Android LetterDeeds 16-18). */
const FORWARDED = "\u21AA\uFE0E Forwarded message", FORWARDED_FROM = "\u21AA\uFE0E Forwarded from ";
const forwardLabel = (qt) => (qt === FORWARDED ? t("Forwarded") : qt?.startsWith(FORWARDED_FROM) ? t("Forwarded from %@", { "%@": qt.slice(FORWARDED_FROM.length) }) : null);

/** THE PICKER OF A FORWARD: the correspondences, the search over them; a choice sends. */
/** A conversation to hand something to: a forward, or a card sent (`title` says which). */
export function ForwardSheet({ from, onPick, onClose, title }) {
  const word = title || t("Forward");
  const [rows, setRows] = useState([]);
  const [q, setQ] = useState("");
  const [me, setMe] = useState(null);
  useEffect(() => { invoke("chats").then((r) => setRows(r.filter((x) => !x.blocked))); invoke("identity_state").then(setMe).catch(() => {}); }, []);
  // the chats tab's list one to one, Saved Messages included under its own word and one's own face (iOS ForwardPickerView)
  const shown = rows.filter((r) => !q.trim() || rowTitle(r.ref, r.name).toLowerCase().includes(q.trim().toLowerCase()));
  return (
    <div className="sheet-shade" onClick={onClose}>
      <div className="meet forward" onClick={(e) => e.stopPropagation()} role="dialog" aria-label={word}>
        <div className="meet-bar">
          <button className="meet-close" onClick={onClose} aria-label={t("Cancel")}><Glyph name="close" size={18} /></button>
          <div className="meet-title">{word}</div>
        </div>
        <input className="meet-field" placeholder={t("Search")} value={q} onChange={(e) => setQ(e.target.value)} aria-label={t("Search")} autoFocus />
        <div className="forward-rows">
          {shown.map((r) => (
            <button key={r.ref} className="forward-row" onClick={() => onPick(r.ref)} aria-label={`${word}: ${rowTitle(r.ref, r.name)}`}>
              {r.ref === SAVED ? <SelfFace name={me?.name} version={me?.face} size={36} /> : <Face chat={r.ref} version={r.face} size={36} />}<span>{rowTitle(r.ref, r.name)}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

/** THE HOUSE'S MOVING PICTURES (iOS MontanaGifPanel): an empty word shows what is popular, a word searches; «GIF» the moving
 *  pictures, «Стикеры» the house's stickers; a tile wears the light picture, the full one is brought only for the one sent. */
function GifPanel({ onPick }) {
  const [kind, setKind] = useState("gif");
  const [q, setQ] = useState("");
  const [found, setFound] = useState(null);
  const [tiles, setTiles] = useState({});
  useEffect(() => {
    let live = true;
    setFound(null);
    const id = setTimeout(() => invoke("gif_search", { q, kind, offset: 0 }).then((r) => { if (live) setFound(r); }).catch(() => live && setFound([])), q ? 400 : 0);
    return () => { live = false; clearTimeout(id); };
  }, [q, kind]);
  useEffect(() => {
    let live = true;
    (async () => {
      for (const f of found || []) {
        if (!live) return;
        if (GIF_TILES.has(f.id)) { setTiles((x) => ({ ...x, [f.id]: GIF_TILES.get(f.id) })); continue; }
        const b = await invoke("gif_get", { id: f.id, full: false }).catch(() => null);
        if (b) { GIF_TILES.set(f.id, b); if (live) setTiles((x) => ({ ...x, [f.id]: b })); }
      }
    })();
    return () => { live = false; };
  }, [found]);
  const pick = async (f) => {
    const b64 = (await invoke("gif_get", { id: f.id, full: true }).catch(() => null)) || tiles[f.id];
    if (!b64) return;
    onPick(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)), kind === "sticker");
  };
  return (
    <div className="gif-panel">
      <div className="gif-head">
        <input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder={t(kind === "sticker" ? "Search stickers" : "Search GIFs")} aria-label={t(kind === "sticker" ? "Search stickers" : "Search GIFs")} />
        <button className={kind === "gif" ? "on" : ""} onClick={() => setKind("gif")}>{t("GIF")}</button>
        <button className={kind === "sticker" ? "on" : ""} onClick={() => setKind("sticker")}>{t("Stickers")}</button>
      </div>
      <div className="gif-grid">
        {found === null && <span className="spinner small" />}
        {found?.length === 0 && <div className="row-caption">{t("Nothing found")}</div>}
        {(found || []).map((f, i) => (
          <button key={f.id} onClick={() => pick(f)} aria-label={`${t(kind === "sticker" ? "Sticker" : "GIF")} ${i + 1}`} style={{ aspectRatio: `${f.w} / ${f.h}` }}>
            {tiles[f.id] ? <img src={`data:image/gif;base64,${tiles[f.id]}`} alt="" /> : null}
          </button>
        ))}
      </div>
    </div>
  );
}
/** The light pictures the tiles already brought, kept while the window lives. */
const GIF_TILES = new Map();

/** A round video note is a minute at most (iOS MontanaVideoNoteCamera). */
const NOTE_MAX_MS = 60000;
/** The letters the person unfolded past the filter, by name, for the life of the window (iOS MTFilterFold). */
const UNFOLDED = new Set();

export default function Conversation({ chat, onBack, narrow, myName, myFace, focus, onOpenChat, forward, onForwardTaken }) {
  const playerFace = player.usePlayer();
  const [talk, setTalk] = useState(null);
  const [, setFolds] = useState(0);   // a letter unfolded past the filter draws again
  const [stickerFor, setStickerFor] = useState(null);   // a sticker letter whose sheet stands open
  const [draft, setDraft] = useState("");
  const [problem, setProblem] = useState(null);
  const [handing, setHanding] = useState(null);   // a big file being handed to the postman: its share, 0..100
  const [unreadFrom, setUnreadFrom] = useState(null);   // the mid the «Unread messages» line stands over, fixed at the opening
  const [menu, setMenu] = useState(null);               // {m, x, y, confirm}
  const saved = chat === SAVED;                          // the room without a wire (iOS isLocalRoom): no marks, no presence, no «for everyone»
  const [album, setAlbum] = useState(null);             // the pictures a tapped one opened among (iOS PhotoPresenter), and where
  // THE CHAT'S PICTURES, OLDEST FIRST, EACH ONCE (iOS ChatStore.pictures(in:)): the ones whose file is here
  const openPicture = (m) => {
    const shots = (talk?.msgs || []).filter((x) => x.file && letterKind(x.text) === "media" && manifestOf(x.text).k === "img");
    const pages = shots.map((x) => {
      const o = manifestOf(x.text);
      return { key: x.mid, cover: o.th ? `data:image/jpeg;base64,${o.th}` : undefined, load: () => urlOf({ mid: x.mid, ext: o.e, big: o.sz > BIG }) };
    });
    const start = pages.findIndex((p) => p.key === m.mid);
    if (start >= 0) setAlbum({ pages, start });
  };
  const [replying, setReplying] = useState(null);       // the letter answered
  const [editing, setEditing] = useState(null);         // my letter whose words change
  const [dropping, setDropping] = useState(false);
  const [seen, setSeen] = useState(null);
  const [typers, setTypers] = useState([]);   // who types in the group now, by name (iOS MTGroupTyping)
  const [reporting, setReporting] = useState(null);   // the letter reported
  const [forwarding, setForwarding] = useState(null);   // the letters forwarded: {mids}
  const [picking, setPicking] = useState(null);         // the letters chosen (iOS selectingMsgs): a Set of mids, or null
  const [thread, setThread] = useState(null);           // the post whose comments are open (iOS MTChannelCommentsSheet)
  const [chessOpen, setChessOpen] = useState(false);    // the pair's game (iOS MTChessScreen), from the head or the invitation
  // THE MONEY FLOW OF THIS CHAT (iOS MTMoneyFlow): the feed's turn, newest on top, the live words both ways; a hold on the coin
  // opens the auto-reactions (the author's word 06.10.2026)
  const [nameMenu, setNameMenu] = useState(null);   // the capsule's menu: «Copy name» (iOS contextMenu)
  useLeave(() => onBack?.(), !!narrow && !!onBack);   // the chat over the list leaves by Esc, as by its back round (iOS edge stroke)
  const [flow, setFlow] = useState(false);
  const [flowBegun, setFlowBegun] = useState(0);        // the coin's one turn in the middle as the flow comes on (MTMoneyFlowBegins)
  const [autoReacts, setAutoReacts] = useState(false);
  const flowHold = useRef({ timer: null, held: false });
  const drafting = useRef({ timer: null, word: null });   // my live words, said at most four times a second
  const fieldNow = useRef({ flow: false, text: "", editing: false });   // what a chat leaving reads of its field (the checkpoint)
  fieldNow.current = { flow, text: draft, editing: !!editing };
  const [plate, setPlate] = useState(null);             // the card of the link in the field (iOS Compose): {url, card}
  const [roster, setRoster] = useState([]);             // the people a «@» may name in a group (iOS mentionable)
  const dropped = useRef(new Set());                    // links the person told to ride bare
  const [panel, setPanel] = useState(null);             // the emoji panel: "emoji" | "stickers" | "gif"
  const [groupPage, setGroupPage] = useState(false);
  const [callMenu, setCallMenu] = useState(false);
  const [roomAsk, setRoomAsk] = useState(null);   // a group's call: the kind chosen, whom to invite next
  const [rec, setRec] = useState(null);                 // a voice being recorded: {started, ctx, stream, node, chunks}
  const [note, setNote] = useState(null);               // a round video note being recorded: {started, stream, recorder, parts}
  const recNow = useRef(null), noteNow = useRef(null);  // the tapes as they stand now, for a release that comes before a render
  recNow.current = rec; noteNow.current = note;
  // THE COMPOSE ROW'S TWO SHAPES (iOS ChatInputBar, @AppStorage composeOpen; the finger alone changes it): folded -- the down arrow,
  // the words, the media key; open -- the words the whole width, the row of keys under them
  const [composeOpen, setComposeOpenNow] = useState(() => { try { return localStorage.getItem("composeOpen") === "1"; } catch { return false; } });
  const setComposeOpen = (v) => { setComposeOpenNow(v); try { localStorage.setItem("composeOpen", v ? "1" : "0"); } catch { /* this run */ } };
  // THE MEDIA KEY'S MODE (iOS @AppStorage composeMediaMode): mic, video, coin -- a tap turns it, a hold records in it
  const [mediaMode, setMediaModeNow] = useState(() => { try { return localStorage.getItem("composeMediaMode") || "mic"; } catch { return "mic"; } });
  const setMediaMode = (v) => { setMediaModeNow(v); try { localStorage.setItem("composeMediaMode", v); } catch { /* this run */ } };
  const [holdHint, setHoldHint] = useState(false);       // «Hold to record» in the field for 1.6 s after a tap
  const [held, setHeld] = useState(null);               // the hold under the pointer: {away, locked}
  const hold = useRef(null);
  const heldLast = useRef(false);
  const [coinBalance, setCoinBalance] = useState(null); // the Available over the field in the coin's mode (iOS MTCoinBalancePlate)
  const [coinSay, setCoinSay] = useState(null);         // the coin send's alert
  const [cardNote, setCardNote] = useState(null);       // my card, to send here (iOS MontanaCardNoteView)
  const photoPicker = useRef(null);
  const noteView = useRef(null);
  const [recTime, setRecTime] = useState(0);
  useEffect(() => {
    if (!rec && !note) return;
    const started = (rec || note).started;
    const id = setInterval(() => {
      setRecTime(Date.now() - started);
      if (note && Date.now() - started >= NOTE_MAX_MS) stopNote(true);   // a note is a minute at most (iOS)
    }, 250);
    return () => clearInterval(id);
  }, [rec, note]);
  useEffect(() => { if (note && noteView.current && noteView.current.srcObject !== note.stream) noteView.current.srcObject = note.stream; });

  /** THE ROUND VIDEO NOTE (iOS MontanaVideoNoteCamera): the camera and the microphone into an MP4 (H.264 and AAC, what every
   *  phone plays), a minute at most; it leaves by the one media road as a video whose manifest says it is round. The camera
   *  runs at the height of the quality chosen in Appearance (iOS MontanaNoteQuality) and its centre square is drawn into the
   *  file's square of 480, which never changes, at the quality's rate. */
  const startNote = async () => {
    setProblem(null);
    const type = ["video/mp4;codecs=avc1.42E01E,mp4a.40.2", "video/mp4"].find((x) => window.MediaRecorder?.isTypeSupported(x));
    if (!type) { setProblem(t("Not sent")); return; }
    const step = NOTE_STEPS[readNoteQuality()];
    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { height: { ideal: step.height }, frameRate: 30 }, audio: { echoCancellation: true, noiseSuppression: true } });
    } catch {
      setProblem(t("The camera is unavailable"));
      return;
    }
    const eye = document.createElement("video");
    eye.muted = true; eye.srcObject = stream;
    await eye.play().catch(() => {});
    const square = document.createElement("canvas");
    square.width = square.height = 480;
    const g = square.getContext("2d");
    const draw = setInterval(() => {
      const w = eye.videoWidth, h = eye.videoHeight, s = Math.min(w, h);
      if (s) g.drawImage(eye, (w - s) / 2, (h - s) / 2, s, s, 0, 0, 480, 480);
    }, 1000 / 30);
    const tape = new MediaStream([...square.captureStream(30).getVideoTracks(), ...stream.getAudioTracks()]);
    invoke("trace", { line: `note camera ${readNoteQuality()} ${stream.getVideoTracks()[0]?.getSettings().height || 0} rate ${step.rate}` }).catch(() => {});
    const parts = [];
    const recorder = new MediaRecorder(tape, { mimeType: type, videoBitsPerSecond: step.rate, audioBitsPerSecond: 64000 });
    recorder.ondataavailable = (e) => { if (e.data?.size) parts.push(e.data); };
    recorder.start(500);
    setRecTime(0);
    setNote({ started: Date.now(), stream, recorder, parts, type, draw, tape });
  };
  const stopNote = async (send) => {
    const n = noteNow.current;
    setNote(null);
    if (!n) return;
    const secs = (Date.now() - n.started) / 1000;
    await new Promise((ok) => { n.recorder.onstop = ok; try { n.recorder.stop(); } catch { ok(); } });
    clearInterval(n.draw);
    n.tape.getTracks().forEach((x) => x.stop());
    n.stream.getTracks().forEach((x) => x.stop());
    if (!send || secs < 1) { if (send) setProblem(t("Too short to send")); return; }
    const file = new File(n.parts, "vnote.mp4", { type: "video/mp4" });
    const q = replying;
    setReplying(null);
    pinned.current = true;
    await sendFile(chat, file, "", q ? { qt: letterPreview(q.text), qm: q.mid } : null, { r: true, du: Math.round(secs * 10) / 10 })
      .catch(() => setProblem(t("Not sent")));
  };

  /** THE MICROPHONE (iOS VoiceRecordButton): the samples gathered as they come, at 48 kHz, mono. */
  const startVoice = async () => {
    setProblem(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } });
      const ctx = new AudioContext({ sampleRate: 48000 });
      const src = ctx.createMediaStreamSource(stream);
      const node = ctx.createScriptProcessor(4096, 1, 1);
      const mute = ctx.createGain();
      mute.gain.value = 0;
      const chunks = [];
      node.onaudioprocess = (e) => chunks.push(new Float32Array(e.inputBuffer.getChannelData(0)));
      src.connect(node); node.connect(mute); mute.connect(ctx.destination);
      setRecTime(0);
      setRec({ started: Date.now(), ctx, stream, node, chunks });
    } catch {
      setProblem(t("No access to the microphone"));
    }
  };
  const stopVoice = async (send) => {
    const r = recNow.current;
    setRec(null);
    if (!r) return;
    r.node.disconnect(); r.stream.getTracks().forEach((x) => x.stop());
    const rate = r.ctx.sampleRate;
    await r.ctx.close();
    if (!send) return;
    const n = r.chunks.reduce((a, c) => a + c.length, 0);
    const pcm = new Int16Array(n);
    let o = 0;
    for (const c of r.chunks) for (let i = 0; i < c.length; i++) pcm[o++] = Math.max(-32768, Math.min(32767, Math.round(c[i] * 32767)));
    const q = replying;
    setReplying(null);
    const head = new TextEncoder().encode(JSON.stringify({ chat, rate, qt: q ? letterPreview(q.text) : undefined, qm: q?.mid }));
    const body = new Uint8Array(4 + head.length + pcm.byteLength);
    new DataView(body.buffer).setUint32(0, head.length, true);
    body.set(head, 4);
    body.set(new Uint8Array(pcm.buffer), 4 + head.length);
    pinned.current = true;
    invoke("chat_send_voice", body).catch(() => setProblem(t("Too short to send")));
  };
  useEffect(() => {
    const first = (draft.match(/https?:\/\/[^\s<>"]+/gi) || []).find((u) => !dropped.current.has(u));
    if (!first || editing) { setPlate(null); return; }
    if (plate && plate.url === first) return;
    let live = true;
    const id = setTimeout(() => invoke("link_card", { text: first }).then((c) => { if (live) setPlate(c ? { url: first, card: c } : null); }).catch(() => {}), 600);
    return () => { live = false; clearTimeout(id); };
  }, [draft, editing]);
  useEffect(() => {
    if (!chat.startsWith("grp:")) { setRoster([]); return; }
    invoke("group_info", { chat }).then((g) => setRoster(g?.kind === "g" ? (g.people || []).filter((p) => !p.me && p.name) : [])).catch(() => {});
  }, [chat, talk?.group?.count]);
  const [exact, setExact] = useState(true);   // my own «Online status»: off, I see others only coarsely (iOS seenExact)
  const lastTyping = useRef(0);
  const feed = useRef(null);
  // THE LETTERS THAT ARRIVE RISE (iOS MTLetterMotion): a letter not in the feed when it first stood rises on the feed's spring,
  // for the spring's own time; the feed as it opens stands still
  const arrived = useRef({ chat: null, known: null, at: new Map() });
  const field = useRef(null);
  const picker = useRef(null);
  const pinned = useRef(true);
  const lastTop = useRef(0);   // where the feed stood at its last scroll: which way it moved
  const readTimer = useRef(null);

  const sayRead = () => {
    clearTimeout(readTimer.current);
    readTimer.current = setTimeout(() => {
      if (document.visibilityState === "visible" && document.hasFocus()) invoke("chat_read", { chat });
    }, 800);
  };
  const look = (first) => invoke("chat_open", { chat }).then((c) => {
    if (!c) return;
    if (first && c.unread > 0) {
      const theirs = c.msgs.filter((m) => !m.mine);
      setUnreadFrom(theirs[Math.max(0, theirs.length - c.unread)]?.mid ?? null);
    }
    setTalk(c);
    if (c.unread > 0) sayRead();
  });
  useEffect(() => {
    setTalk(null); setDraft(""); setProblem(null); setUnreadFrom(null); setMenu(null); setReplying(null); setEditing(null); setPicking(null); setAlbum(null);
    pinned.current = true;
    lastTop.current = 0;
    look(true);
    field.current?.focus();
    const back = () => sayRead();
    window.addEventListener("focus", back);
    return () => { window.removeEventListener("focus", back); clearTimeout(readTimer.current); };
  }, [chat]);
  useChanged(() => look(false));
  // THE UNSENT WORDS STAY WITH THE CHAT (iOS persistDraft / ChatStore.draft): the field's words kept for this chat at every change,
  // sealed on this computer -- an edit in the field keeps none, a sent letter empties them at once; the chat opens with them, and
  // the list, told as the chat is left, shows them under its name
  const keptWords = useRef({ chat: null, pending: null, timer: null });   // `chat`: the chat whose kept words came back to the field
  const chatNow = useRef(chat);
  chatNow.current = chat;
  useEffect(() => {
    const k = keptWords.current;
    k.chat = null;
    invoke("chat_kept_draft", { chat }).then((d) => {
      if (chatNow.current !== chat) return;
      k.chat = chat;
      if (d) setDraft((now) => now || d);   // words typed before the disk answered stand
    }).catch(() => { if (chatNow.current === chat) k.chat = chat; });
    const flush = () => {
      clearTimeout(k.timer);
      const p = k.pending;
      k.pending = null;
      return p ? invoke("chat_keep_draft", p).catch(() => {}) : Promise.resolve();
    };
    const hid = () => { if (document.visibilityState === "hidden") flush(); };
    document.addEventListener("visibilitychange", hid);
    return () => {
      document.removeEventListener("visibilitychange", hid);
      flush().then(() => window.dispatchEvent(new Event("montana-drafts")));
    };
  }, [chat]);
  useEffect(() => {
    const k = keptWords.current;
    if (k.chat !== chat) return;
    const text = editing ? "" : draft;
    k.pending = { chat, text };
    clearTimeout(k.timer);
    k.timer = setTimeout(() => {
      const p = k.pending;
      k.pending = null;
      if (p) invoke("chat_keep_draft", p).catch(() => {});
    }, text ? 400 : 0);
  }, [draft, editing, chat]);
  // the presence line: asked at the opening, when the lane moves, and every 15 s (a word lives 45 s from its moment)
  useEffect(() => {
    const ask = () => invoke("presence", { chat }).then(setSeen).catch(() => {});
    ask();
    invoke("settings_get").then((s) => setExact(s.presenceSharing !== false));
    const id = setInterval(ask, 15000);
    let stop = null, gone = false;
    listen("montana://presence", (e) => { if (e.payload === chat) ask(); }).then((u) => { if (gone) u(); else stop = u; });
    return () => { clearInterval(id); gone = true; stop && stop(); };
  }, [chat]);
  // the chat's own Money Flow, read as it opens (a group's feed never turns); the chat closing or the window hiding freezes their
  // bubble of my words at the field's state (iOS sendDraftCheckpoint) -- an edit in the field is no draft
  useEffect(() => {
    setFlow(false); setAutoReacts(false);
    if (!chat.startsWith("grp:")) invoke("money_flow", { chat }).then(setFlow).catch(() => {});
    const checkpoint = () => {
      const f = fieldNow.current;
      if (!f.flow) return;
      invoke("chat_draft", { chat, text: f.text.trim() && !f.editing ? f.text : "", caret: -1, rm: null, ck: true }).catch(() => {});
    };
    const hid = () => { if (document.visibilityState === "hidden") checkpoint(); };
    document.addEventListener("visibilitychange", hid);
    return () => {
      document.removeEventListener("visibilitychange", hid);
      clearTimeout(drafting.current.timer); drafting.current = { timer: null, word: null };
      checkpoint();
    };
  }, [chat]);
  // NO BANNER WHILE A PERSON PLAYS (iOS MTPlayQuiet): a chess board before the eyes
  useEffect(() => {
    invoke("play_quiet", { on: chessOpen }).catch(() => {});
    return () => { invoke("play_quiet", { on: false }).catch(() => {}); };
  }, [chessOpen]);
  /** My live words (iOS sendDraft): the newest field said at most four times a second while the flow is on; an empty field, or the
   *  letter sent, ends them. */
  const sayDraft = (text, caret, rm) => {
    drafting.current.word = { text, caret, rm };
    if (drafting.current.timer) return;
    drafting.current.timer = setTimeout(() => {
      const w = drafting.current.word;
      drafting.current.timer = null;
      if (w) invoke("chat_draft", { chat, text: w.text, caret: w.caret, rm: w.rm || null }).catch(() => {});
    }, 250);
  };
  const endDraft = () => {
    clearTimeout(drafting.current.timer);
    drafting.current = { timer: null, word: null };
    invoke("chat_draft", { chat, text: "", caret: 0, rm: null }).catch(() => {});
  };
  /** THE COIN TURNS THE FEED (iOS flipMark): on -- the chat's row «the money flow began», the coin's turn in the middle, the feed at
   *  its newest end (the top) and the field taking the keys; off -- my live words end on their screen and theirs leave mine. */
  const turnFlow = async () => {
    const on = await invoke("money_flow", { chat, on: !flow }).catch(() => flow);
    setFlow(on);
    invoke("trace", { line: `feed_turn newest_first=${on ? 1 : 0}` }).catch(() => {});
    if (on) {
      setFlowBegun((n) => n + 1);
      setComposeOpen(true);   // the flow opens the row (iOS flipMark: composeOpen = true): the field above, the keys below
      pinned.current = true;
      look(false);
      setTimeout(() => { if (feed.current) feed.current.scrollTop = 0; field.current?.focus(); }, 350);
      if (draft.trim() && !editing) sayDraft(draft, field.current?.selectionStart ?? draft.length, replying?.mid);
    }
  };
  useEffect(() => {
    if (!flowBegun) return;
    const id = setTimeout(() => setFlowBegun(0), 1800);
    return () => clearTimeout(id);
  }, [flowBegun]);
  // who types in a group: asked when the walk says it moved, and again each second while anyone types, till the typing life ends
  useEffect(() => {
    setTypers([]);
    if (!chat.startsWith("grp:")) return;
    let timer = null, stop = null, gone = false;
    const ask = () => invoke("group_typing", { chat }).then((names) => {
      if (gone) return;
      setTypers(names);
      clearTimeout(timer);
      if (names.length) timer = setTimeout(ask, 1000);
    }).catch(() => {});
    ask();
    listen("montana://presence", (e) => { if (e.payload === chat) ask(); }).then((u) => { if (gone) u(); else stop = u; });
    return () => { gone = true; clearTimeout(timer); stop && stop(); };
  }, [chat]);
  // the feed stays at its newest end while it stood there: the bottom, or the top of the turned feed of the Money Flow
  useLayoutEffect(() => {
    if (pinned.current && feed.current) feed.current.scrollTop = flow ? 0 : feed.current.scrollHeight;
  }, [talk, flow, seen?.draft]);
  // a picture or a film that comes in after the opening grows the feed under the newest letter: the feed stays at its end while
  // it stood there (iOS stickBottom, the author's word 01.09: «the last letter, whatever it is, must be scrolled all the way down»)
  useEffect(() => {
    const f = feed.current;
    if (!f || typeof ResizeObserver === "undefined") return undefined;
    const keep = new ResizeObserver(() => { if (pinned.current) f.scrollTop = flow ? 0 : f.scrollHeight; });
    for (const row of f.children) keep.observe(row);
    return () => keep.disconnect();
  }, [talk, flow]);
  // a letter the search found: the feed goes to it once it stands
  const focused = useRef(null);
  useEffect(() => {
    if (!focus) { focused.current = null; return; }   // cleared, so the same letter may be asked again (iOS ui.showLetter)
    if (!talk || focused.current === focus) return;
    focused.current = focus;
    pinned.current = false;
    setTimeout(() => jump(focus), 50);
  }, [talk, focus]);

  // the letters a page of this chat chose, forwarded through this chat's own picker (iOS pendingForwardMany)
  useEffect(() => {
    if (!talk || !forward?.length) return;
    const inFeed = talk.msgs.filter((m) => forward.includes(m.mid)).map((m) => m.mid);   // in the feed's order
    setForwarding({ mids: inFeed.length === forward.length ? inFeed : forward });
    onForwardTaken?.();
  }, [talk, forward]);

  const send = async () => {
    const text = draft.replace(/^ +| +$/g, "");   // spaces off, newlines kept (iOS sendMessage)
    if (!text.trim()) return;
    setProblem(null);
    if (editing) {
      if (text !== editing.text) await invoke("chat_edit", { chat, mid: editing.mid, text }).catch(() => setProblem(t("Not sent")));
      setEditing(null); setDraft("");
      return;
    }
    if (talk?.group && !talk.group.owner) {
      // the group's rights and its slow mode are asked before the field empties itself (iOS refusal): nothing typed is lost
      const why = await invoke("group_refusal", { chat, words: text }).catch(() => null);
      if (why) { setProblem(refusalWords(why)); return; }
    }
    const q = replying;
    const lp = plate && text.includes(plate.url) ? plate.card : null;   // the card the person saw rides (iOS attachable)
    setDraft(""); setReplying(null); setPlate(null); dropped.current = new Set();
    pinned.current = true;
    if (flow) endDraft();   // the sender's clear is welcome (iOS): the letter itself ends the draft on their side as well
    try {
      await invoke("chat_send", { chat, text, qt: q ? letterPreview(q.text) : null, qm: q ? q.mid : null, lp });
      look(false);
      invoke("trace", { line: `lp_send card=${lp ? 1 : 0} pic=${cardOf(lp || "")?.p ? 1 : 0}` }).catch(() => {});
      if (lp) catchPicture(chat, lp).then((ok) => ok && look(false));   // the picture is a second read (iOS MTLinkCards.picture)
    } catch (e) {
      setDraft(text); setReplying(q);
      setProblem(t("Not sent"));
    }
  };

  /** Files from the picker, a drop or the clipboard: each one a letter; the words in the field become the first one's caption
   *  (iOS: a pasted picture goes with the text as its caption); a reply rides the first. */
  // THE COIN'S MODE (iOS coinMode): only a pair takes coins; the field takes the sum, the key sends it
  const coinsHere = !talk?.group && !talk?.blocked;
  const coinMode = mediaMode === "coin" && coinsHere && !rec && !note;
  const coinAmount = coinMode ? Number(draft.replace(/\D/g, "").slice(0, 15)) || 0 : 0;
  useEffect(() => {
    if (!coinMode) return undefined;
    let live = true;
    const read = () => invoke("wallet_state", {}).then((s) => { if (live) setCoinBalance(s.available); }).catch(() => {});
    read();
    const id = setInterval(read, 3000);
    return () => { live = false; clearInterval(id); };
  }, [coinMode]);
  /** THE COINS GO BY THE FIELD (iOS onSendCoin): a sum the Available holds, as the wallet's send does it -- a record on my chain, a
   *  letter in the chat; short, the platform's alert says so. */
  const sendCoins = async () => {
    if (!coinMode) return;
    if (coinAmount <= 0) { setMediaMode("mic"); return; }
    if (coinBalance != null && coinAmount > coinBalance) { setCoinSay(["Not enough coins", "Your coin balance is lower than this."]); return; }
    const out = await invoke("coin_send", { chat, coins: coinAmount }).catch(() => "refused");
    invoke("trace", { line: `coin send field out=${String(out).split(":")[0]} coins=${coinAmount}` }).catch(() => {});
    if (String(out).startsWith("sent:")) { setDraft(""); pinned.current = true; look(false); return; }
    setCoinSay(out === "pending" ? ["Transfer is being confirmed", null] : ["Coins were not sent", null]);
  };
  /** THE MEDIA KEY (iOS sendColumn, MontanaHoldControl): a tap shorter than 0.19 s turns the mode -- microphone, camera, coin --; a
   *  hold records in it; let go it sends, carried 100 to the left it cancels, carried 60 up it locks and rolls on hands-free. */
  const mediaDown = (e) => {
    if (e.button !== 0 || rec || note) return;
    e.currentTarget.setPointerCapture?.(e.pointerId);
    const h = { x: e.clientX, y: e.clientY, held: false, away: false, locked: false, up: false };
    hold.current = h;
    h.timer = setTimeout(async () => {
      h.held = true;
      setHeld({ away: false, locked: false });
      if (mediaMode === "video") await startNote(); else await startVoice();
      if (h.up) endHold(h);   // let go while the tape was being born
    }, 190);
  };
  const mediaMove = (e) => {
    const h = hold.current;
    if (!h || !h.held || h.locked) return;
    const dx = e.clientX - h.x, dy = e.clientY - h.y;
    h.away = dx < -100;
    if (dy < -60 && -dy > Math.abs(dx)) h.locked = true;
    setHeld({ away: h.away, locked: h.locked });
  };
  const mediaUp = () => {
    const h = hold.current;
    if (!h) return;
    clearTimeout(h.timer);
    if (!h.held) { hold.current = null; return; }   // a tap: its click turns the mode
    h.up = true;
    heldLast.current = true;   // the click that follows a hold turns nothing
    endHold(h);
  };
  /** The tap turns the mode -- the pointer's, the keyboard's, the reader's alike (a tap mid-recording turns nothing) -- and says how a
   *  tape is made. */
  const mediaTap = () => {
    if (heldLast.current) { heldLast.current = false; return; }
    if (rec || note) return;
    setMediaMode(mediaMode === "mic" ? "video" : mediaMode === "video" && coinsHere ? "coin" : "mic");
    setHoldHint(true);
    setTimeout(() => setHoldHint(false), 1600);
  };
  const endHold = (h) => {
    if (h.locked) { hold.current = null; setHeld(null); return; }   // the tape rolls on: its bar's bin and send
    if (!recNow.current && !noteNow.current) return;                  // not born yet: its birth ends it
    hold.current = null;
    setHeld(null);
    if (recNow.current) stopVoice(!h.away); else stopNote(!h.away);
  };
  const emojiKey = (
    <button className={composeOpen ? "glass-mark small" : "emoji-key"} onClick={() => setPanel(panel ? null : "emoji")} aria-label={t("Emoji")}>
      <Glyph name={panel ? "keyboard" : "faceSmiling"} size={20} color="var(--bar-glyph)" />
    </button>
  );
  const mediaColumn = coinMode ? (
    <button key="coin" className="media-key" onClick={sendCoins} aria-label={t(coinAmount > 0 ? "Send coins" : "Coin")}>
      <MintCoin side={36} />
    </button>
  ) : draft.trim() && !rec && !note ? (
    <button key="send" className="send" onClick={send} aria-label={t("Send")}><img src={sendButton} alt="" /></button>
  ) : (
    <button key="media" className={"media-key" + (hold.current?.held ? " holding" : "")} aria-label={t(mediaMode === "video" ? "Video message" : "Voice message")}
            onPointerDown={mediaDown} onPointerMove={mediaMove} onPointerUp={mediaUp} onPointerCancel={mediaUp} onClick={mediaTap}>
      <img src={mediaMode === "video" ? videoKey : voiceKey} alt="" draggable={false} />
    </button>
  );
  /** The tape's bar over the field: while held, what letting go does (iOS «Release to send» / «Release to cancel») and the lock's
   *  way up; locked or started by hand, the bin and the send. */
  const recBar = (cancel, done, extra = "") => (
    <div className={"rec-bar" + extra} role="status">
      <span className="rec-dot" /><span className="rec-time">{`${Math.floor(recTime / 60000)}:${String(Math.floor(recTime / 1000) % 60).padStart(2, "0")}`}</span>
      <span className="grow" />
      {held && !held.locked ? (
        <>
          <span className={"rec-hint" + (held.away ? " red" : "")}>{t(held.away ? "Release to cancel" : "Release to send")}</span>
          <span className="rec-lock" aria-hidden="true"><Glyph name="lock" size={16} color="var(--bar-glyph)" /></span>
        </>
      ) : (
        <>
          <button className="unblock" onClick={cancel}>{t("Cancel")}</button>
          <button className="send" onClick={done} aria-label={t("Send")}><img src={sendButton} alt="" /></button>
        </>
      )}
    </div>
  );
  /** MY CARD, SENT HERE (iOS the row's card key, MontanaCardNoteView): the card as it stands, its send. */
  const openCardNote = async () => {
    const c = await invoke("card_get").catch(() => null);
    const lines = c ? cardLines(c).filter(Boolean) : [];
    if (lines.length) setCardNote(lines); else window.dispatchEvent(new CustomEvent("montana-open-pane", { detail: "card" }));
  };
  const sendFiles = async (files) => {
    const list = [...files].filter((f) => f.size > 0);
    if (!list.length) return;
    const caption = draft.trim(), q = replying;
    if (talk?.group && !talk.group.owner) {
      for (const f of list) {
        const k = f.type.startsWith("image/") ? "img" : f.type.startsWith("video/") ? "vid" : f.type.startsWith("audio/") ? "aud" : "doc";
        const why = await invoke("group_refusal", { chat, words: "\u200B\u200BMD:" + JSON.stringify({ k, n: f.name, cap: caption }) }).catch(() => null);
        if (why) { setProblem(refusalWords(why)); return; }
      }
    }
    setDraft(""); setReplying(null); setProblem(null);
    pinned.current = true;
    for (let i = 0; i < list.length; i++) {
      await sendFile(chat, list[i], i === 0 ? caption : "", i === 0 && q ? { qt: letterPreview(q.text), qm: q.mid } : null, {}, setHanding)
        .catch(() => setProblem(t("Not sent")))
        .finally(() => setHanding(null));
    }
  };

  const open = (e, m) => {
    e.preventDefault();
    if (picking) return;
    const w = window.innerWidth, h = window.innerHeight;
    setMenu({ m, x: Math.min(e.clientX, w - 250), y: Math.min(e.clientY, h - 380), confirm: false });
    if (!m.mine) invoke("wallet_state", {}).then((s) => setMenu((x) => (x && x.m === m ? { ...x, balance: s.balance } : x))).catch(() => {});
  };
  const giveCoins = async (n) => {
    const m = menu.m;
    setMenu(null);
    if (!(await invoke("chat_coin", { chat, mid: m.mid, coins: n }).catch(() => false))) setProblem(`${t("Not enough coins")}: ${t("Your coin balance is lower than this.")}`);
  };
  const deed = async (what) => {
    const m = menu.m;
    setMenu(null);
    if (what === "reply") { setEditing(null); setReplying(m); field.current?.focus(); }
    if (what === "copy") invoke("copy_text", { text: letterKind(m.text) === "sticker" ? m.text.slice(2) : m.text });
    if (what === "edit") { setReplying(null); setEditing(m); setDraft(m.text); field.current?.focus(); }
    if (what === "mine" || what === "everyone") invoke("chat_delete", { chat, mids: [m.mid], everyone: what === "everyone" });
    if (what === "report") setReporting(m);
    if (what === "forward") setForwarding({ mids: [m.mid] });
    if (what === "select") setPicking(new Set([m.mid]));
    if (what === "pinBoth" || what === "pinMe") invoke("chat_pin", { chat, mid: m.mid, on: true, both: what === "pinBoth" });
    if (what === "unpin") invoke("chat_pin", { chat, mid: m.mid, on: false, both: true });
  };
  /** THE CHOSEN LETTERS (iOS selectionBar): a tap takes one in or out; the last one out ends the choosing. */
  const flip = (mid) => {
    const next = new Set(picking);
    if (next.has(mid)) next.delete(mid); else next.add(mid);
    setPicking(next.size ? next : null);
  };
  const chosen = () => talk.msgs.filter((m) => picking?.has(m.mid));   // in the feed's order
  const pickedDeed = (what) => {
    const list = chosen();
    if (!list.length) return;
    if (what === "delete") invoke("chat_delete", { chat, mids: list.map((m) => m.mid), everyone: false });   // iOS deleteSelected: for me
    if (what === "share") {
      // the system's share sheet, as iOS's (a file's letter gives its caption or its name); the clipboard when it will not open
      const words = list.map((m) => letterKind(m.text) === "media" ? (manifestOf(m.text).cap || manifestOf(m.text).n || "") : letterKind(m.text) === "sticker" ? m.text.slice(2) : m.text)
        .filter(Boolean).join("\n\n");
      invoke("share_text", { title: "Montana", text: words, link: null }).catch(() => false).then((shown) => {
        if (!shown) { invoke("copy_text", { text: words }); setProblem(t("Copied")); }
      });
    }
    if (what === "forward") setForwarding({ mids: list.map((m) => m.mid) });
    setPicking(null);
  };
  /** A VOICE OF THIS CHAT IN THE ONE PLAYER (iOS onPlayVoice): the chat's voices on this computer behind it in feed order, each
   *  with its speaker -- auto-next walks forward. */
  const hearVoice = (m, at) => {
    const voices = talk.msgs.filter((x) => letterKind(x.text) === "media" && manifestOf(x.text).k === "aud" && x.file)
      .map((x) => ({ file: x.mid, mid: x.mid, ext: manifestOf(x.text).e, sender: x.mine ? myName : (x.speaker || chatName(talk.name)) }));
    const v = voices.find((x) => x.file === m.mid) || { file: m.mid, mid: m.mid, ext: manifestOf(m.text).e, sender: m.mine ? myName : chatName(talk.name) };
    player.playVoice(v, voices, chat, v.sender, at ?? null);
  };
  const jump = (mid) => {
    const el = feed.current?.querySelector(`[data-mid="${CSS.escape(mid)}"]`);
    if (el) { el.scrollIntoView({ block: "center", behavior: "smooth" }); el.classList.add("flash"); setTimeout(() => el.classList.remove("flash"), 900); }
  };

  if (!talk) return <section className="talk" />;
  const playing = !!playerFace.file;
  const last = talk.msgs[talk.msgs.length - 1];
  const channel = talk.group?.kind === "c";
  // a channel's subscriber only reads (iOS MTChannelSubscriberBar); its administrator with «Post Messages» writes
  const listener = channel && !talk.group.owner && !(talk.group.admin && (talk.group.rights || []).includes("po"));
  const typing = talk.group && !channel && !talk.group.left && !talk.group.removed ? typingLine(typers) : null;
  // THE LINE UNDER THE NAME IS SAID WITH THE NAME (iOS chatTitleBubble reads as one element: the name, then «in chat», «typing…», the
  // members): the capsule is one button, whose children a screen reader never reaches, so its label carries the line too
  const titleLine = talk.group
    ? typing || (talk.group.removed ? t("you were removed from the group") : talk.group.left ? t("you have left the group") : people(talk.group.kind, talk.group.count))
    : !saved && seenText(seen, exact) ? seenText(seen, exact)[0] : "";
  const byMid = new Map(talk.msgs.map((m) => [m.mid, m]));
  // THE PAIR'S GAME WHILE IT IS PLAYED (iOS chessPlayed, MTChessSend.playedGame): the newest invitation's game, not finished; an
  // invitation of theirs not yet answered waits for me in the feed (iOS awaitsMe)
  const chessPlayed = (() => {
    const entries = [];
    for (const m of talk.msgs) { const l = chessLetter(m.text); if (l) entries.push({ letter: l, mine: m.mine, mid: m.mid }); }
    const cur = entries.length ? chessCurrent(entries) : null;
    if (!cur) return null;
    const own = entries.filter((e) => e.letter.game === cur);
    const g = chessReplay(own, cur);
    if (!g || chessFinished(g.status)) return null;
    const invite = own.find((e) => e.letter.kind === "invite");
    return { id: cur, invite: invite?.mid, awaitsMe: g.status === "invited" && !!invite && !invite.mine };
  })();
  const kept = arrived.current;
  if (kept.chat !== chat || !kept.known) { arrived.current = { chat, known: new Set(talk.msgs.map((m) => m.mid)), at: new Map() }; }
  const now = Date.now();
  for (const m of talk.msgs) {
    if (!arrived.current.known.has(m.mid)) { arrived.current.known.add(m.mid); arrived.current.at.set(m.mid, now); }
  }
  const rising = (mid) => now - (arrived.current.at.get(mid) || 0) < 1500;
  const authorOf = (qm) => (byMid.get(qm)?.mine ? myName : chatName(talk.name));
  // their live words at the feed's newest end; words that already stand as a letter of theirs are no draft (iOS peerLetterStands)
  const live = flow && seen?.draft && !talk.msgs.slice(-20).some((m) => !m.mine && m.text.trim() === seen.draft.trim()) ? (() => {
    const q = seen.draft_rm ? byMid.get(seen.draft_rm) : null;
    return <LiveDraft key="live-draft" text={seen.draft} caret={seen.draft_c} quote={q ? { who: authorOf(q.mid), words: letterPreview(q.text) } : null} />;
  })() : null;
  // THE RIBBON OF TIME (iOS newestFirst): the flow's feed stands newest on top
  const turned = (rows) => (flow ? [live, ...rows.reverse()] : [...rows, live]);
  return (
    <section className={"talk" + (dropping ? " dropping" : "") + (flow ? " flow" : "") + (playing ? " playing" : "")} data-ref={talk.ref}
             onDragOver={(e) => { if (e.dataTransfer.types.includes("Files")) { e.preventDefault(); setDropping(true); } }}
             onDragLeave={(e) => { if (!e.currentTarget.contains(e.relatedTarget)) setDropping(false); }}
             onDrop={(e) => { e.preventDefault(); setDropping(false); sendFiles(e.dataTransfer.files); }}>
      <ChatGround chat={talk.ref} />
      {picking && (
        <header className="talk-bar select-top">
          <span className="select-count">{t("Selected: %lld").replace("%lld", picking.size)}</span>
          <button className="glass-mark" onClick={() => setPicking(null)} aria-label={t("Cancel")}><Glyph name="close" size={18} color="var(--bar-glyph)" /></button>
        </header>
      )}
      <header className={"talk-bar" + (picking ? " hidden" : "")}>
        {narrow && <button className="glass-mark" onClick={onBack} aria-label={t("Back")}><Glyph name="back" size={18} color="var(--bar-glyph)" /></button>}
        {/* THE CAPSULE TAKES THE ROW (iOS chatTitleBubble: maxWidth .infinity): a tap opens the person's page -- a group's its own --,
            a hold (here the right button) copies the name */}
        <div className="title-bubble pressable" role="button" tabIndex={0}
             onClick={() => (talk.group ? setGroupPage(true) : window.dispatchEvent(new CustomEvent("montana-person", { detail: { ref: talk.ref } })))}
             onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.click(); }}
             onContextMenu={(e) => { e.preventDefault(); setNameMenu({ x: e.clientX, y: e.clientY }); }}
             aria-label={[rowTitle(talk.ref, talk.name), titleLine].filter(Boolean).join(", ")}>
          {saved ? <SelfFace name={myName} version={myFace} size={36} />
            : talk.group ? <GroupFace size={36} chat={talk.ref} version={talk.face} /> : <Face chat={talk.ref} version={talk.face} size={36} />}
          <div className="title-words">
            <div className="title-name">{rowTitle(talk.ref, talk.name)}</div>
            {talk.group && (typing
              ? <div className="title-seen"><span className="seen-dot live" />{typing}</div>
              : <div className="title-seen">{talk.group.removed ? t("you were removed from the group") : talk.group.left ? t("you have left the group") : people(talk.group.kind, talk.group.count)}</div>
            )}
            {!talk.group && !saved && seenText(seen, exact) && (
              <div className="title-seen"><span className={"seen-dot" + (seenText(seen, exact)[1] ? " live" : "")} />{seenText(seen, exact)[0]}</div>
            )}
          </div>
        </div>
        {/* the marks stand while the chat's coin does (iOS coinStands): never in Saved Messages, which has no pipe */}
        {!talk.group && !talk.blocked && !saved && (
          // THE WALLET BESIDE THE COIN (iOS walletMark): the platform's wallet glyph on the marks' round; a tap lays the wallet's page
          // over the chat
          <button className="glass-mark call-mark" onClick={() => window.dispatchEvent(new Event("montana-wallet"))} aria-label={t("TimeCoin")}>
            <Glyph name="wallet" size={20} color="var(--bar-glyph)" />
          </button>
        )}
        {!talk.group && !talk.blocked && !saved && (
        // THE FEED'S TURN IS OUR MINT COIN (iOS flipMark): it spins while the flow is on, the ring stands with it; a hold of half a
        // second opens the auto-reactions and the lift that ends it turns nothing
        <button className={"glass-mark call-mark flow-mark" + (flow ? " on" : "")} aria-label={t("Money Flow")} aria-pressed={flow}
                onPointerDown={() => {
                  clearTimeout(flowHold.current.timer);
                  flowHold.current.held = false;
                  flowHold.current.timer = setTimeout(() => { flowHold.current.held = true; setAutoReacts(true); }, 500);
                }}
                onPointerUp={() => clearTimeout(flowHold.current.timer)}
                onPointerLeave={() => clearTimeout(flowHold.current.timer)}
                onContextMenu={(e) => { e.preventDefault(); setAutoReacts(true); }}
                onClick={() => { if (flowHold.current.held) { flowHold.current.held = false; return; } turnFlow(); }}>
          <MintCoin side={22} spinning={flow} />
        </button>
      )}
        {!talk.group && !talk.blocked && !saved && (
        // THE CHESS MARK (iOS chessMark): the platform's blue ring only while the pair's game is played; a tap leads to an invitation
        // that waits for my answer in the feed, enters the game that is played, or -- none -- opens the board's new game
        <button className={"glass-mark call-mark" + (chessPlayed ? " on" : "")} aria-pressed={!!chessPlayed}
                onClick={() => (chessPlayed?.awaitsMe ? jump(chessPlayed.invite) : setChessOpen(true))} aria-label={`${t("Chess")}: ${chatName(talk.name)}`}>
          <img className="knight-mark" src={knight} alt="" />   {/* iOS MTChessIcon (Chesswn) 22 x 22 */}
        </button>
      )}
        {talk.group && !talk.group.left && !talk.group.removed && (
          <RoomMark chat={chat} kinds={talk.group.rooms || []} onAsk={(kind, video) => setRoomAsk({ kind, video })} />
        )}
        {!talk.group && !talk.blocked && !saved && (
        <button className="glass-mark call-mark" onClick={() => setCallMenu(!callMenu)} aria-label={t("Call")}>
          <Glyph name="calls" size={20} color="var(--bar-glyph)" />
        </button>
      )}
      </header>
      {nameMenu && (
        <div className="menu-shade" onClick={() => setNameMenu(null)} onContextMenu={(e) => { e.preventDefault(); setNameMenu(null); }}>
          <div className="letter-menu" style={{ left: Math.min(nameMenu.x, window.innerWidth - 260), top: nameMenu.y }} onClick={(e) => e.stopPropagation()} role="menu">
            <div className="menu-rows">
              <button className="menu-row" role="menuitem" onClick={() => { setNameMenu(null); invoke("copy_text", { text: chatName(talk.name) }).catch(() => {}); }}>
                <span>{t("Copy name")}</span><Glyph name="copy" size={18} />
              </button>
            </div>
          </div>
        </div>
      )}
      {callMenu && (
        <div className="menu-shade" onClick={() => setCallMenu(false)}>
          <div className="letter-menu call-menu" onClick={(e) => e.stopPropagation()} role="menu">
            <div className="menu-rows">
              <button className="menu-row" role="menuitem" onClick={() => { setCallMenu(false); callTo(chat, talk.name, false); }}><span>{t("Voice Call")}</span><Glyph name="calls" size={18} /></button>
              <button className="menu-row" role="menuitem" onClick={() => { setCallMenu(false); callTo(chat, talk.name, true); }}><span>{t("Video Call")}</span><Glyph name="video" size={18} /></button>
            </div>
          </div>
        </div>
      )}
      {talk.group && <RoomBar chat={chat} />}
      {roomAsk && <RoomInvite chat={chat} kind={roomAsk.kind} video={roomAsk.video} opening onClose={() => setRoomAsk(null)} />}
      {talk.pins.length > 0 && (() => {
        const p = byMid.get(talk.pins[talk.pins.length - 1]);
        return p && (
          <button className="pinned-bar" onClick={() => jump(p.mid)}>
            <span className="pinned-line" />
            <span className="pinned-words"><b>{t("Pinned message")}</b><span>{letterPreview(p.text)}</span></span>
            <Glyph name="pin" size={14} color="var(--gray)" />
          </button>
        );
      })()}
      <div className="feed" ref={feed}
           onScroll={(e) => {
             // the end pins the feed; only a move toward older letters lets it go -- a feed grown under its end by a picture
             // that came in is no move of the person's
             const f = e.currentTarget;
             const end = flow ? f.scrollTop < 40 : f.scrollHeight - f.scrollTop - f.clientHeight < 40;
             const away = flow ? f.scrollTop > lastTop.current : f.scrollTop < lastTop.current;
             if (end) pinned.current = true; else if (away) pinned.current = false;
             lastTop.current = f.scrollTop;
           }}>
        {talk.msgs.length === 0 && (
          <div className="feed-empty">
            <div className="feed-empty-title">{t("No messages yet")}</div>
            <div className="feed-empty-text">{t("Write the first one — it will wait for them on a node")}</div>
          </div>
        )}
        {turned(talk.msgs.map((m, i) => {
          const prev = talk.msgs[i - 1];
          const newDay = !prev || startOfDay(prev.at) !== startOfDay(m.at);
          const apart = prev && (prev.mine !== m.mine || m.at - prev.at >= 600000);   // a new speaker or ten minutes: 8 more
          const kind = letterKind(m.text);
          const meta = (
            <span className="meta">
              {m.views > 0 && <span className="views" role="img" aria-label={`${t("Views")}: ${m.views}`}><Eye />{views(m.views)}</span>}
              {m.sign && <span className="signature">{m.sign}</span>}
              {m.edited && <span className="edited">{t("edited")}</span>}
              {m.mine && m.state === -1 && <FailedMark />}
              {hourOf(m.at)}
              {/* the letter's gematria, the same on both sides; the head of its seal while the ribbon of time stands (iOS metaLine) */}
              {m.gem > 0 && <span className="gem">{"· " + m.gem}</span>}
              {flow && m.seal && <span className="seal" aria-hidden="true">{"· " + m.seal}</span>}
            </span>
          );
          const answers = [...new Set([m.peer_react, m.my_react].filter(Boolean))];
          if (m.event) {
            return (
              <div key={m.mid} className="feed-item">
                {newDay && <div className="day-pill">{dayTitle(m.at)}</div>}
                <div className="event-row">{m.text}</div>
              </div>
            );
          }
          // a channel speaks as itself: the channel's name over the words at the head of a run (iOS MTChannelPostLook.head)
          const speaker = !m.mine && m.seat && (!prev || prev.seat !== m.seat || prev.event || apart) ? (channel ? talk.name : m.speaker) : null;
          return (
            <div key={m.mid} className={"feed-item" + (rising(m.mid) ? " rising" : "")}>
              {newDay && <div className="day-pill">{dayTitle(m.at)}</div>}
              {m.mid === unreadFrom && <div className="unread-line">{t("Unread messages")}</div>}
              <div className={"bubble-row " + (m.mine ? "mine" : "theirs") + (apart && !newDay ? " apart" : "") + (picking ? " picking" : "")}
                   onClick={picking ? () => flip(m.mid) : undefined}>
                {picking && <span className={"pick-mark" + (picking.has(m.mid) ? " on" : "")} role="checkbox" aria-checked={picking.has(m.mid)}
                                  aria-label={`${t("Select")}: ${letterPreview(m.text)}`}>{picking.has(m.mid) ? "✓" : ""}</span>}
                {m.text === FLOW_ROW ? (
                  // THE MONEY FLOW BEGAN (iOS MTMoneyFlowRow): the chess invitation's card, our coin turning once as the row appears
                  <div className="bubble flow-card" data-mid={m.mid}>
                    <div className="flow-card-row">
                      <MintCoin side={40} turn={0} />
                      <span className="flow-card-words"><b>{t("Money flow has begun")}</b><span>{t("Every letter mints a coin")}</span></span>
                    </div>
                    {meta}
                  </div>
                ) : m.secret ? (
                  // A SECRET SHARED (iOS MTSecretLetter): its title only -- the machine line never stands in the feed -- and the way into
                  // my own Passwords, which open by Windows Hello
                  <div className="bubble secret-card" data-mid={m.mid} onContextMenu={(e) => open(e, m)}>
                    <span className="secret-title">{m.text}</span>
                    {!m.mine && <button className="secret-save" onClick={(e) => {
                      e.stopPropagation();
                      invoke("secret_take", { chat, mid: m.mid }).then((ok) => setProblem(ok ? t("Saved") : t("Not saved")))
                        .catch((why) => setProblem(String(why) === "notset" ? t("Set up Windows Hello: without it the passwords cannot be protected.") : t("The passwords did not open.")));
                    }}>{t("Save to Passwords")}</button>}
                    {meta}
                  </div>
                ) : m.hidden && !UNFOLDED.has(m.mid) ? (
                  // THE FILTER (iOS filterFolds, Guideline 1.2): their letter carrying an objectionable word stands folded; the tap
                  // unfolds it for the life of the window, every drawing of it (iOS MTFilterFold)
                  <button className="bubble filter-fold" data-mid={m.mid} onClick={(e) => { e.stopPropagation(); UNFOLDED.add(m.mid); setFolds((x) => x + 1); }}>
                    <span>{t("Hidden by the filter")}</span><span className="row-caption">{t("Tap to show")}</span>
                  </button>
                ) : kind === "sticker" ? (
                  <div className="sticker" data-mid={m.mid} onContextMenu={(e) => open(e, m)}>{m.text.slice(2)}{meta}</div>
                ) : (
                  <div className={"bubble" + (kind === "media" ? " media-bubble k-" + (manifestOf(m.text).k || "doc") + (/^stick_/i.test(manifestOf(m.text).n || "") || manifestOf(m.text).n === "montana-card" ? " bare" : "") : "")}
                       onClick={kind === "media" && manifestOf(m.text).n === "montana-card" && !picking ? () => setStickerFor(m.mid) : undefined}
                       data-mid={m.mid} data-state={m.state} onContextMenu={(e) => open(e, m)}>
                    {speaker && <span className="speaker" style={{ color: tint(channel ? talk.ref : `gm:${talk.ref.slice(4)}/${m.seat}`) }}>{speaker}</span>}
                    {forwardLabel(m.qt) && <span className="forwarded">{forwardLabel(m.qt)}</span>}
                    {m.qm && (
                      <button className="quote" onClick={() => jump(m.qm)}>
                        <span className="quote-who">{authorOf(m.qm)}</span>
                        <span className="quote-words">{m.qt}</span>
                      </button>
                    )}
                    {kind === "media" ? (
                      <>
                        <MediaBody chat={chat} m={m} onVoice={picking ? undefined : (at) => hearVoice(m, at)} onPicture={picking ? undefined : openPicture} />
                        {manifestOf(m.text).cap && <span className="bubble-text media-cap">{manifestOf(m.text).cap}</span>}
                      </>
                    ) : chessLetter(m.text)?.kind === "invite" ? (
                      <button className="chess-card" onClick={(e) => { e.stopPropagation(); setChessOpen(true); }}
                              aria-label={`${t("Chess")} · ${chessSeat(m.text, m.mine)}`}>
                        <span className="chess-card-title">♟ {t("Chess")}</span><span className="row-caption">{chessSeat(m.text, m.mine)}</span>
                      </button>
                    ) : <span className="bubble-text"><Linked text={m.text} /></span>}
                    {m.lp && <LinkCard lp={m.lp} />}
                    {meta}
                  </div>
                )}
                {m.comments >= 0 && (
                  <button className="comments-foot" onClick={(e) => { e.stopPropagation(); setThread(m); }}>
                    {m.comments > 0 ? `${t("Comments")}: ${m.comments}` : t("Leave a Comment")}
                  </button>
                )}
                {answers.length > 0 && (
                  <div className="answers">
                    {answers.map((e) => (
                      <button key={e} className={"answer" + (e === m.my_react ? " mine" : "")}
                              onClick={() => e === m.my_react && invoke("chat_react", { chat, mid: m.mid, emoji: e })}>
                        {e}{m.peer_react === e && m.my_react === e ? " 2" : ""}
                      </button>
                    ))}
                  </div>
                )}
                {/* the stage under my newest letter -- none in a room without a wire (iOS rowStatus nil for a local room) */}
                {m === last && m.mine && m.text !== FLOW_ROW && !saved && (
                  <div className="ladder" data-rung={m.state}>
                    <Dots rung={m.state === -1 ? 0 : m.state} /><span>{ladderWord(m.state)}</span>
                  </div>
                )}
              </div>
            </div>
          );
        }))}
      </div>
      {problem && <div className="talk-problem">{problem}</div>}
      {handing !== null && <div className="talk-note" role="status">{t("Preparing the file")}: {handing}%</div>}
      {(() => {
        // THE PLATE OF «@» (iOS MTMentionCompose): it follows the word typed after «@»; a name taken stands in the field
        const at = roster.length ? /(^|\s)@([^\s@]*)$/.exec(draft) : null;
        const named = at ? roster.filter((p) => p.name.toLowerCase().startsWith(at[2].toLowerCase())).slice(0, 6) : [];
        if (!named.length || picking) return null;
        return (
          <div className="mention-plate" role="listbox" aria-label="@">
            {named.map((p) => (
              <button key={p.seat} role="option" className="mention-row" style={{ color: tint(`gm:${chat.slice(4)}/${p.seat}`) }}
                      onClick={() => { setDraft(draft.slice(0, at.index + at[1].length) + "@" + p.name + " "); field.current?.focus(); }}>
                @{p.name}
              </button>
            ))}
          </div>
        );
      })()}
      {/* THE PLATES OVER THE FIELD (iOS barPlate, in its order: edit, reply, the coin's balance, the link's card): the bar's own plate of 36
          -- the glyph, the title in the accent's colour, the words on one line -- and its square close of 36; under the field in the flow */}
      {(replying || editing) && !picking && (
        <div className="compose-quote">
          <button className="compose-plate" onClick={() => jump((editing || replying).mid)}>
            <Glyph name={editing ? "pencil" : "reply"} size={14} color="var(--ink)" />
            <span className="compose-plate-words">
              <b>{editing ? t("Editing") : t("Reply to %@").replace("%@", authorOf(replying.mid))}</b>
              <span>{letterPreview((editing || replying).text)}</span>
            </span>
          </button>
          <button className="glass-mark small" aria-label={t("Cancel")} onClick={() => { if (editing) setDraft(""); setReplying(null); setEditing(null); }}>
            <Glyph name="close" size={16} color="var(--bar-glyph)" />
          </button>
        </div>
      )}
      {coinMode && !picking && (
        <div className="compose-quote">
          <div className="compose-plate">
            <MintCoin side={22} />
            <span className="compose-plate-words"><span className="row-caption">{t("Available")}</span><b className="digits">{coinBalance == null ? "…" : count(coinBalance)}</b></span>
          </div>
          <button className="glass-mark small" aria-label={t("Close")} onClick={() => { setMediaMode("mic"); setDraft(""); }}>
            <Glyph name="close" size={16} color="var(--bar-glyph)" />
          </button>
        </div>
      )}
      {plate && !picking && (
        <div className="compose-quote">
          <div className="compose-plate">
            <Glyph name="link" size={14} color="var(--ink)" />
            <span className="compose-plate-words">
              <b>{cardOf(plate.card)?.s || t("Link previews")}</b>
              <span>{cardOf(plate.card)?.t || cardOf(plate.card)?.d || plate.url}</span>
            </span>
          </div>
          <button className="glass-mark small" aria-label={t("Cancel")} onClick={() => { dropped.current.add(plate.url); setPlate(null); }}>
            <Glyph name="close" size={16} color="var(--bar-glyph)" />
          </button>
        </div>
      )}
      {/* THE PLAYER FLOATS OVER THE FEED'S BOTTOM, ABOVE THE MESSAGE FIELD (iOS MontanaConversation, the author's word 14.09): the
          letters scroll behind its glass; the feed keeps its room so the newest letter stands above it; a voice of this chat goes
          to its letter here */}
      <div className="player-dock">
        <PlayerBar onGoTo={(c, mid) => (c === chat ? jump(mid) : window.dispatchEvent(new CustomEvent("montana-show-letter", { detail: { chat: c, mid } })))} />
      </div>
      {picking ? (
        <footer className="compose select-bar">
          <button className="select-tool red" onClick={() => pickedDeed("delete")} aria-label={t("Delete")}><Glyph name="trash" size={20} /><span>{t("Delete")}</span></button>
          <button className="select-tool" onClick={() => pickedDeed("share")} aria-label={t("Share")}><Glyph name="share" size={20} /><span>{t("Share")}</span></button>
          <button className="select-tool" onClick={() => pickedDeed("forward")} aria-label={t("Forward")}><ForwardGlyph size={20} /><span>{t("Forward")}</span></button>
        </footer>
      ) : talk.group && (talk.group.left || talk.group.removed) ? (
        <footer className="compose blocked-bar">
          <span className="row-caption">{talk.group.removed ? t("you were removed from the group") : t("you have left the group")}</span>
        </footer>
      ) : listener ? (
        <footer className="compose blocked-bar subscriber-bar">
          <button className="mute-wide" onClick={() => { invoke("chat_flag", { chat, flag: "mute", on: !talk.muted }).then(() => look(false)); }}>
            {talk.muted ? t("Unmute") : t("Mute")}
          </button>
        </footer>
      ) : talk.blocked ? (
        <footer className="compose blocked-bar">
          <span className="blocked-pill">{t("Blocked")}</span>
          <button className="unblock" onClick={() => invoke("chat_block", { chat, on: false })}>{t("Unblock")}</button>
        </footer>
      ) : (<>
      {panel && !talk.blocked && (
        <div className="emoji-panel" role="dialog" aria-label={t("Emoji")}>
          <div className="emoji-tabs">
            <button className={panel === "emoji" ? "on" : ""} onClick={() => setPanel("emoji")}>{t("Emoji")}</button>
            <button className={panel === "stickers" ? "on" : ""} onClick={() => setPanel("stickers")}>{t("Stickers")}</button>
            <button className={panel === "gif" ? "on" : ""} onClick={() => setPanel("gif")}>{t("GIF")}</button>
          </div>
          {panel === "gif" ? <GifPanel onPick={(bytes, sticker) => {
            setPanel(null); pinned.current = true;
            const q = replying; setReplying(null);
            // A MOVING PICTURE LEAVES AS A FILE (iOS sendGifFound): the document road touches no byte of it, and its name says
            // which of the two it is -- gif_ a moving picture, stick_ a sticker of the house drawn bare
            const file = new File([bytes], `${sticker ? "stick" : "gif"}_${crypto.randomUUID()}.gif`, { type: "application/octet-stream" });
            sendFile(chat, file, "", q ? { qt: letterPreview(q.text), qm: q.mid } : null).catch(() => setProblem(t("Not sent")));
          }} /> : panel === "stickers" ? <StickerPanel emoji={STICKERS}
              onPick={(name) => {
                setPanel(null); pinned.current = true;
                const q = replying; setReplying(null);
                invoke("sticker_send", { chat, name, qt: q ? letterPreview(q.text) : null, qm: q?.mid ?? null }).catch(() => setProblem(t("Not sent")));
              }}
              onEmoji={(e) => { setPanel(null); pinned.current = true; invoke("chat_send", { chat, text: "\u2063\u2063" + e, qt: null, qm: null }).then(() => look(false)); }} /> : (
          <div className={"emoji-grid" + (panel === "stickers" ? " big" : "")}>
            {(panel === "emoji" ? EMOJI : STICKERS).map((e) => (
              <button key={e} aria-label={e} onClick={() => {
                if (panel === "emoji") { setDraft((d) => d + e); field.current?.focus(); }
                else { setPanel(null); pinned.current = true; invoke("chat_send", { chat, text: "\u2063\u2063" + e, qt: null, qm: null }).then(() => look(false)); }
              }}>{e}</button>
            ))}
          </div>
          )}
        </div>
      )}
      {/* THE FIELD'S TIER (iOS ChatInputBar part .field): folded, the down arrow, the words with the emoji key inside, the media key;
          open, the words the whole width -- the keys stand on the tier under it */}
      <footer className={"compose" + (composeOpen ? " open" : "")}>
        <input ref={picker} type="file" multiple hidden onChange={(e) => { sendFiles(e.target.files); e.target.value = ""; }} />
        <input ref={photoPicker} type="file" accept="image/*,video/*" multiple hidden onChange={(e) => { sendFiles(e.target.files); e.target.value = ""; }} />
        {!composeOpen && (
          <button className="glass-mark small compose-key" onClick={() => { if (rec || note) return; setPanel(null); setComposeOpen(true); }} aria-label={t("More")}>
            <Glyph name="chevronDown" size={20} color="var(--bar-glyph)" />
          </button>
        )}
        <div className="compose-box">
          <textarea ref={field} rows={1} className="compose-field" value={draft}
                    placeholder={coinMode ? t("Enter the coin amount") : holdHint ? t("Hold to record") : t("Message...")}
                    aria-label={coinMode ? t("Enter the coin amount") : t("Message...")} inputMode={coinMode ? "numeric" : undefined}
                    onChange={(e) => {
                      // the coin's sum is digits alone, fifteen at most; commas and spaces are let be (iOS coinAmount)
                      const v = coinMode ? e.target.value.replace(/[^\d ,]/g, "") : e.target.value;
                      setDraft(v);
                      if (coinMode) return;
                      if (flow && !editing) sayDraft(v, e.target.selectionStart ?? v.length, replying?.mid);
                      // I type: TY: at most every 3 s while the field holds words (iOS MontanaConversation 4428-4436)
                      if (v.trim() && !editing && Date.now() - lastTyping.current > 3000) {
                        lastTyping.current = Date.now();
                        invoke("chat_typing", { chat });
                      }
                    }}
                    onPaste={(e) => { if (e.clipboardData.files.length) { e.preventDefault(); sendFiles(e.clipboardData.files); } }}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); if (coinMode) sendCoins(); else send(); }
                      if (e.key === "Escape" && (replying || editing)) { e.preventDefault(); if (editing) setDraft(""); setReplying(null); setEditing(null); }
                    }} />
          {!composeOpen && emojiKey}
        </div>
        {!composeOpen && mediaColumn}
        {rec && recBar(() => stopVoice(false), () => stopVoice(true))}
        {note && (
          <div className="note-shade" role="dialog" aria-label={t("Video message")}>
            <video ref={noteView} className="note-round" autoPlay playsInline muted />
            {recBar(() => stopNote(false), () => stopNote(true), " note-bar")}
          </div>
        )}
      </footer>
      {/* THE ROW OF KEYS (iOS actionRow / glyphRow): the up arrow folds it back, the emoji, the gallery, the card, the file -- a place and
          a contact of the phone's own book Windows keeps none of -- and the media key or the send at its end, each a round of 36 */}
      {composeOpen && (
        <footer className="compose-row" role="toolbar" aria-label={t("Message...")}>
          <button className="glass-mark small" onClick={() => { if (!rec && !note) setComposeOpen(false); }} aria-label={t("Less")}>
            <span className="glyph-up"><Glyph name="chevronDown" size={20} color="var(--bar-glyph)" /></span>
          </button>
          {emojiKey}
          <button className="glass-mark small" onClick={() => photoPicker.current?.click()} aria-label={t("Gallery")}><Glyph name="photo" size={20} color="var(--bar-glyph)" /></button>
          <button className="glass-mark small" onClick={openCardNote} aria-label={t("Business card")}><Glyph name="card" size={20} color="var(--bar-glyph)" /></button>
          <button className="glass-mark small" onClick={() => picker.current?.click()} aria-label={t("Files")}><Glyph name="doc" size={20} color="var(--bar-glyph)" /></button>
          {mediaColumn}
        </footer>
      )}
      {coinSay && (
        <div className="alert-shade" onClick={() => setCoinSay(null)}>
          <div className="alert" role="alertdialog" onClick={(e) => e.stopPropagation()}>
            <div className="alert-title">{t(coinSay[0])}</div>
            {coinSay[1] && <div className="alert-text">{t(coinSay[1])}</div>}
            <div className="alert-keys"><button className="bold" onClick={() => setCoinSay(null)}>{t("OK")}</button></div>
          </div>
        </div>
      )}
      {cardNote && (
        <Page title={t("Business card")} onClose={() => setCardNote(null)}>
          <div className="card-note"><CardFace lines={cardNote} width={320} /></div>
          <Section>
            <button className="set-row accent" onClick={async () => { const l = cardNote; setCardNote(null); try { await sendCard(chat, l); } catch { setProblem(t("Not sent")); } }}>
              <span className="row-title" style={{ color: "var(--blue)" }}>{t("Send")}</span>
            </button>
          </Section>
        </Page>
      )}
      </>)}
      {groupPage && <GroupPage chat={chat} onClose={() => setGroupPage(false)} onGone={() => { setGroupPage(false); onBack?.(); }} />}
      {stickerFor && <StickerSheet mid={stickerFor} onClose={() => setStickerFor(null)} />}
      {chessOpen && <ChessBoard chat={chat} name={chatName(talk.name)} onClose={() => { setChessOpen(false); look(false); }} />}
      {autoReacts && <AutoReacts onClose={() => setAutoReacts(false)} />}
      {flowBegun > 0 && (
        <div className="flow-begins" aria-hidden="true">
          <MintCoin side={120} turn={flowBegun} />
          <b>{t("Money Flow")}</b>
        </div>
      )}
      {thread && <Thread chat={chat} post={thread} title={talk.name} onClose={() => { setThread(null); look(false); }} />}
      {reporting && <ReportPage chat={chat} name={talk.name} letter={reporting} onClose={() => setReporting(null)} />}
      {album && <PhotoAlbum pages={album.pages} start={album.start} onClose={() => setAlbum(null)} />}
      {forwarding && <ForwardSheet onClose={() => setForwarding(null)}
                                   onPick={async (to) => {
                                     const mids = forwarding.mids;
                                     setForwarding(null);
                                     for (const mid of mids) await invoke("chat_forward", { chat, mid, to });   // in the feed's order
                                     onOpenChat?.(to);
                                   }} />}
      {menu && (
        <div className="menu-shade" onClick={() => setMenu(null)} onContextMenu={(e) => { e.preventDefault(); setMenu(null); }}>
          <div className="letter-menu" style={{ left: menu.x, top: menu.y }} onClick={(e) => e.stopPropagation()} role="menu">
            {!menu.confirm && !(listener && !talk.group.reacts) && (
              <div className="answers-row">
                {(channel && (talk.group.react_list || []).length ? talk.group.react_list : REACTIONS).slice(0, 9).map((e) => (
                  <button key={e} className={e === menu.m.my_react ? "on" : ""} aria-label={e}
                          onClick={async () => {
                            const m = menu.m;
                            setMenu(null);
                            const why = talk.group && !talk.group.owner ? await invoke("group_refusal", { chat, words: "\u200B\u200BRC:{}" }).catch(() => null) : null;
                            if (why) setProblem(refusalWords(why)); else invoke("chat_react", { chat, mid: m.mid, emoji: e });
                          }}>{e}</button>
                ))}
              </div>
            )}
            <div className="menu-rows">
              {menu.confirm ? (
                <>
                  <div className="menu-ask">{t("Delete message?")}</div>
                  {!saved && <MenuRow icon="trash" label={t("Delete for everyone")} red onClick={() => deed("everyone")} />}
                  <MenuRow icon="trash" label={t("Delete for me")} red onClick={() => deed("mine")} />
                  <MenuRow icon="close" label={t("Cancel")} onClick={() => setMenu({ ...menu, confirm: false })} />
                </>
              ) : (
                <>
                  {!listener && <MenuRow icon="reply" label={t("Reply")} onClick={() => deed("reply")} />}
                  {/* COINS ON THE CORRESPONDENT'S LETTER (iOS onCoin, the author's words 03.10): one coin, or one of π's boxes the
                      balance holds -- the book pays or refuses */}
                  {!menu.m.mine && !talk.group && (
                    <div className="menu-coins">
                      <button className="menu-row" role="menuitem" onClick={() => giveCoins(1)}><span>{t("Give a coin")}</span><span className="coin-mark">Ɉ</span></button>
                      <div className="coin-boxes">
                        {PI_BOXES.map((n) => (
                          <button key={n} disabled={n > (menu.balance ?? 0)} onClick={() => giveCoins(n)} aria-label={`+${shortBox(n)}`}>+{shortBox(n)}</button>
                        ))}
                      </div>
                    </div>
                  )}
                  <MenuRow icon="forward" label={t("Forward")} onClick={() => deed("forward")} />
                  {talk.pins.includes(menu.m.mid)
                    ? <MenuRow icon="pinSlash" label={t("Unpin")} onClick={() => deed("unpin")} />
                    : <>
                        <MenuRow icon="pin" label={t("Pin for both")} onClick={() => deed("pinBoth")} />
                        <MenuRow icon="pin" label={t("Pin for me")} onClick={() => deed("pinMe")} />
                      </>}
                  {letterKind(menu.m.text) !== "media" && <MenuRow icon="copy" label={t("Copy")} onClick={() => deed("copy")} />}
                  <MenuRow icon="checkCircle" label={t("Select")} onClick={() => deed("select")} />
                  {menu.m.mine && letterKind(menu.m.text) === "text" && <MenuRow icon="pencil" label={t("Edit")} onClick={() => deed("edit")} />}
                  {!listener && <MenuRow icon="trash" label={t("Delete")} red onClick={() => setMenu({ ...menu, confirm: true })} />}
                  {!menu.m.mine && <MenuRow icon="report" label={t("Report")} red onClick={() => deed("report")} />}
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

/** THE COMMENTS OF A POST (iOS MTChannelCommentsSheet): the post's words over the comments, each with its speaker's name in
 *  its colour, and the field «Комментарий» at the foot. */
function Thread({ chat, post, title, onClose }) {
  const [list, setList] = useState([]);
  const [words, setWords] = useState("");
  const [problem, setProblem] = useState(null);
  const look = () => invoke("channel_comments", { chat, post: post.mid }).then(setList).catch(() => {});
  useEffect(() => { look(); }, [post.mid]);
  useChanged(look);
  const send = async () => {
    const w = words.trim();
    if (!w) return;
    setProblem(null);
    if (await invoke("channel_comment", { chat, post: post.mid, text: w }).catch(() => false)) { setWords(""); look(); }
    else setProblem(t("Not sent"));
  };
  return (
    <div className="sheet-shade" onClick={onClose}>
      <div className="thread" role="dialog" aria-label={t("Comments")} onClick={(e) => e.stopPropagation()}>
        <div className="thread-head"><span>{t("Comments")}</span>
          <button className="glass-mark" onClick={onClose} aria-label={t("Close")}><Glyph name="close" size={16} color="#fff" /></button>
        </div>
        <div className="thread-post"><span className="speaker" style={{ color: tint(chat) }}>{title}</span>{letterPreview(post.text)}</div>
        <div className="thread-list">
          {list.length === 0 && <div className="row-caption center">{t("No comments here yet...")}</div>}
          {list.map((c) => (
            <div key={c.id} className={"thread-row" + (c.mine ? " mine" : "")}>
              {!c.mine && <span className="speaker" style={{ color: tint(`gm:${chat.slice(4)}/${c.seat}`) }}>{c.name || t("Member")}</span>}
              <span>{c.text}</span>
            </div>
          ))}
        </div>
        {problem && <div className="talk-problem">{problem}</div>}
        <div className="thread-field">
          <input className="compose-field" placeholder={t("Comment")} aria-label={t("Comment")} value={words} maxLength={4096}
                 onChange={(e) => setWords(e.target.value)} onKeyDown={(e) => e.key === "Enter" && send()} />
          <button className="send" onClick={send} aria-label={t("Send")}><img src={sendButton} alt="" /></button>
        </div>
      </div>
    </div>
  );
}

/** The head's line while people type in a group (iOS MTGroupTyping.line): one name, two names, a name and how many others. */
function typingLine(names) {
  const n = names.map((x) => x || t("Member"));
  if (n.length === 0) return null;
  if (n.length === 1) return t("\\(a) is typing…", { a: n[0] });
  if (n.length === 2) return t("\\(a) and \\(b) are typing…", { a: n[0], b: n[1] });
  return t("\\(a) and \\(b) others are typing…", { a: n[0], b: n.length - 1 });
}

/** A card's words, read from its JSON; nothing when it is no card. */
/** A JPEG of a picture, its longer side at most `side`, cut down in quality until it fits `cap` bytes (iOS jpegB64). */
async function jpeg(bitmap, side, q, cap) {
  const k = Math.min(1, side / Math.max(bitmap.width, bitmap.height));
  const c = document.createElement("canvas");
  c.width = Math.max(1, Math.round(bitmap.width * k)); c.height = Math.max(1, Math.round(bitmap.height * k));
  c.getContext("2d").drawImage(bitmap, 0, 0, c.width, c.height);
  for (let quality = q; quality >= 0.3; quality -= 0.1) {
    const blob = await new Promise((r) => c.toBlob(r, "image/jpeg", quality));
    if (blob && blob.size <= cap) {
      const bytes = new Uint8Array(await blob.arrayBuffer());
      let bin = "";
      for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      return btoa(bin);
    }
  }
  return null;
}
/** THE CARD'S PICTURE (iOS MTLinkPreviewBuilder.picture + fitting): read after the words, made a JPEG of 720 at most, and cut to the
 *  card's 16 KB (480, then 320) or left off; the card that learned it lands on my letter (and rides a group's word). */
async function catchPicture(chat, lp) {
  const card = cardOf(lp);
  if (!card || !card.p || card.i) return false;
  try {
    const raw = await invoke("link_picture", { url: card.p });
    const bitmap = await createImageBitmap(new Blob([new Uint8Array(raw)]));
    const full = { ...card, w: bitmap.width, h: bitmap.height };
    for (const [side, q, cap] of [[720, 0.75, 70 * 1024], [480, 0.6, 11 * 1024], [320, 0.5, 8 * 1024]]) {
      full.i = await jpeg(bitmap, side, q, cap);
      if (full.i && JSON.stringify(full).length <= 16384) {
        const ok = await invoke("chat_card", { chat, lp: JSON.stringify(full) });
        invoke("trace", { line: `lp_picture landed=${ok} px=${bitmap.width}x${bitmap.height} side=${side}` }).catch(() => {});
        return ok;
      }
    }
    invoke("trace", { line: "lp_picture none fits" }).catch(() => {});
  } catch (e) {
    invoke("trace", { line: `lp_picture refused ${String(e).slice(0, 60)}` }).catch(() => {});   // a letter without its picture is an ordinary letter
  }
  return false;
}

function cardOf(lp) {
  try { const c = JSON.parse(lp); return c && typeof c.u === "string" ? c : null; } catch { return null; }
}

/** THE CARD UNDER A LETTER (iOS MTLinkPreview's card): the site, the title, the words about the page, and its picture when the card
 *  carries one -- a big one across the card under the words, a small one as a square beside them (iOS wide: 400 by 200 and up);
 *  a tap opens the link in the browser. A pair's envelope carries the words alone (iOS's envelope leg). */
function LinkCard({ lp }) {
  const c = cardOf(lp);
  if (!c) return null;
  const pic = c.i ? `data:image/jpeg;base64,${c.i}` : null;
  const wide = (c.w || 0) >= 400 && (c.h || 0) >= 200;
  return (
    <div className={"link-card" + (pic && !wide ? " small" : "")} role="link" tabIndex={0} title={c.u}
         onClick={(e) => { e.stopPropagation(); invoke("open_link", { url: c.u }); }}
         onKeyDown={(e) => { if (e.key === "Enter") { e.stopPropagation(); invoke("open_link", { url: c.u }); } }}>
      {pic && !wide && <img className="link-card-thumb" src={pic} alt="" role="img" aria-label={t("Link picture")} />}
      <span className="link-card-text">
        {c.s && <span className="link-card-site">{c.s}</span>}
        {c.t && <span className="link-card-title">{c.t}</span>}
        {c.d && <span className="link-card-words">{c.d}</span>}
      </span>
      {pic && wide && <img className="link-card-picture" src={pic} alt="" role="img" aria-label={t("Link picture")} />}
    </div>
  );
}

/** A letter's words with their links alive: a tap opens the link in the browser (http and https alone). A post's words wear the
 *  same (iOS MTPostText: MTLinks.marked). A wall's own link (montana://wall/…) opens its post here, by the one road of every link
 *  (iOS MTPostLinkPeek → MTBoardComments.open; App hears «montana-wall-link»). */
export function Linked({ text }) {
  const parts = [];
  const re = /(?:https?|montana):\/\/[^\s<>"]+/gi;
  let at = 0, m;
  while ((m = re.exec(text))) {
    const link = m[0].replace(/[.,;:!?)\]}»'…]+$/, "");
    if (/^montana:/i.test(link) && !/^montana:\/\/wall\//i.test(link)) { re.lastIndex = m.index + link.length; continue; }
    const wall = /^montana:/i.test(link);
    if (m.index > at) parts.push(text.slice(at, m.index));
    parts.push(<a key={m.index} href="#" className="letter-link" onClick={(e) => {
      e.preventDefault(); e.stopPropagation();
      if (wall) window.dispatchEvent(new CustomEvent("montana-wall-link", { detail: link })); else invoke("open_link", { url: link });
    }}>{link}</a>);
    at = m.index + link.length;
    re.lastIndex = at;
  }
  if (at < text.length) parts.push(text.slice(at));
  return parts.length ? parts : text;
}

/** The eye under a channel's post (iOS «eye.fill»). */
function Eye() {
  return (
    <svg width="13" height="9" viewBox="0 0 26 18" aria-hidden="true" className="eye">
      <path d="M13 0C7 0 2.3 3.9 0 9c2.3 5.1 7 9 13 9s10.7-3.9 13-9C23.7 3.9 19 0 13 0zm0 15a6 6 0 1 1 0-12 6 6 0 0 1 0 12zm0-9.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7z" fill="currentColor" />
    </svg>
  );
}

/** The short count under a post (iOS MTChannelPostLook.count): «999», «1.2K», «3M» -- the tenth only where it is not a zero. */
function views(n) {
  const dot = (0.1).toLocaleString(locale).charAt(1);
  const short = (unit, mark) => { const tenth = Math.floor((n % unit) / (unit / 10)); return Math.floor(n / unit) + (tenth ? dot + tenth : "") + mark; };
  return n >= 1e6 ? short(1e6, "M") : n >= 1e3 ? short(1e3, "K") : String(n);
}

/** One row of the letter's menu (iOS MTMenuRow): the words, the glyph on the right; a destructive one in red. */
export function MenuRow({ icon, label, red, onClick }) {
  return (
    <button className={"menu-row" + (red ? " red" : "")} role="menuitem" onClick={onClick}>
      <span>{label}</span>{icon === "forward" ? <ForwardGlyph size={18} /> : <Glyph name={icon} size={18} />}
    </button>
  );
}
/** FORWARD (iOS arrowshape.turn.up.right): the reply's arrow turned to the right -- the shipped glyphs carry none of its own. */
export function ForwardGlyph({ size, color }) {
  return <span className="glyph-mirror"><Glyph name="reply" size={size} color={color} /></span>;
}
