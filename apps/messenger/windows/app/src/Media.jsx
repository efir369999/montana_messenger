import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { mtSize, t } from "./strings.js";
import { keptPictures } from "./caches.js";
import { Glyph } from "./TopBar.jsx";
import * as player from "./player.js";

const MEDIA = "​​MD:";

/** The manifest a letter carries (MD:), or {} when it names one not unfolded yet. */
export function manifestOf(text) {
  try { return JSON.parse(text.slice(MEDIA.length)); } catch { return {}; }
}

const MIME = { jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", gif: "image/gif", webp: "image/webp", bmp: "image/bmp",
               mp4: "video/mp4", m4v: "video/mp4", mov: "video/mp4", webm: "video/webm", m4a: "audio/mp4", aac: "audio/aac",
               mp3: "audio/mpeg", ogg: "audio/ogg", wav: "audio/wav", pdf: "application/pdf",
               heic: "image/png", heif: "image/png" };   // a HEIF picture comes from media_get as PNG

/** A file larger than this is kept by its pieces and never comes to the window whole (media.rs MAX_SEND). */
export const BIG = 200 * 1024 * 1024;
const PIECE = 512 * 1024;

/** A HEIC or HEIF picture a person picks (an iPhone's photo): WebView2 does not open it, Windows' own imaging gives its PNG. */
export const isHeif = (file) => /^image\/hei[cf]/.test(file.type) || /\.(heic|heif)$/i.test(file.name || "");
async function heifPng(file) {
  return isHeif(file) && file.size <= BIG ? invoke("picture_png", new Uint8Array(await file.arrayBuffer())).catch(() => null) : null;
}
/** A picked picture as an address the page can draw: a HEIF one as its PNG, any other as it is. */
export async function drawableUrl(file) {
  const png = await heifPng(file);
  return URL.createObjectURL(png ? new Blob([png], { type: "image/png" }) : file);
}

/** The file of a letter as an address the window can draw, fetched once and kept while the window lives; a big one is played
 *  through the file road, a range at a time (lib.rs file_range). */
const urls = keptPictures(new Map());
export function useFile(mid, has, ext, big) {
  const [url, setUrl] = useState(urls.get(mid) || null);
  useEffect(() => {
    if (has && big && !urls.has(mid)) urls.set(mid, `http://mtfile.localhost/${mid}.${(ext || "bin").replace(/[^a-z0-9]/gi, "")}`);
    if (!has || urls.has(mid)) { setUrl(urls.get(mid) || null); return; }
    let live = true;
    invoke("media_get", { mid }).then((buf) => {
      const u = URL.createObjectURL(new Blob([buf], { type: MIME[(ext || "").toLowerCase()] || "application/octet-stream" }));
      urls.set(mid, u);
      if (live) setUrl(u);
    }).catch(() => {});
    return () => { live = false; };
  }, [mid, has]);
  return url;
}

/** The address the one player plays (player.js): a letter's file as useFile gives it; a lent folder's track read where it lies
 *  (music_track), one at a time -- the one before is let go, an album is never held in memory. */
let lentUrl = null;
const wallUrls = new Map();
export async function urlOf({ mid, ext, big, lent, file, wall }) {
  if (wall) {   // a post's track, brought once from its wall (wall_file) and kept while the window lives
    if (!wallUrls.has(file)) {
      const buf = await invoke("wall_file", wall);
      wallUrls.set(file, URL.createObjectURL(new Blob([buf], { type: MIME[(ext || "").toLowerCase()] || "application/octet-stream" })));
    }
    return wallUrls.get(file);
  }
  if (lent) {
    const b = await invoke("music_track", { id: file });
    if (lentUrl) URL.revokeObjectURL(lentUrl);
    lentUrl = URL.createObjectURL(new Blob([new Uint8Array(b)], { type: MIME[(ext || "").toLowerCase()] || "application/octet-stream" }));
    return lentUrl;
  }
  if (big && !urls.has(mid)) urls.set(mid, `http://mtfile.localhost/${mid}.${(ext || "bin").replace(/[^a-z0-9]/gi, "")}`);
  if (!urls.has(mid)) {
    const buf = await invoke("media_get", { mid });
    urls.set(mid, URL.createObjectURL(new Blob([buf], { type: MIME[(ext || "").toLowerCase()] || "application/octet-stream" })));
  }
  return urls.get(mid);
}

/** A document letter that is a moving picture (gif_…) or a house's sticker (stick_…), by its name as iOS gives it. */
export const GIF_NAME = /^(gif|stick)_[^/\\]+\.gif$/i;

const NOTES_READ = new Set();

/** A file's size as iOS says it under a file (MontanaMedia: .byteCount(style: .file)); nothing when the size is not known. */
export function sizeText(n) {
  return n ? mtSize(n) : "";
}

const duration = (s) => (s ? `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}` : "");

// ── A FILE OF MINE ON ITS WAY (iOS MTTransferBoard): one ring for the whole road -- a film 0…30 % its writing, 30…100 % its pieces;
// anything else 0…100 % its pieces -- and the word over it ──
const RIDING = new Map();   // mid -> { share, word }
const HEARD = new Set();
let hearing = false;
function hearRiding() {
  if (hearing) return;
  hearing = true;
  invoke("media_board").then((b) => { b.forEach((x) => RIDING.set(x.mid, x)); HEARD.forEach((f) => f()); }).catch(() => {});
  listen("montana://transfer", (e) => {
    const x = e.payload;
    if (x.share == null) RIDING.delete(x.mid); else RIDING.set(x.mid, x);
    HEARD.forEach((f) => f(x.mid));
  });
}
function useRiding(mid) {
  const [, nudge] = useState(0);
  useEffect(() => {
    if (!mid) return undefined;
    hearRiding();
    const f = (which) => { if (!which || which === mid) nudge((n) => n + 1); };
    HEARD.add(f);
    return () => { HEARD.delete(f); };
  }, [mid]);
  return mid ? RIDING.get(mid) || null : null;
}
/** The pill's word: «In queue» while another film is written, «Compressing» and its share once its own writing began, else the
 *  share of the whole road (iOS: «Compressing \(pct)%» stays English there -- here it speaks the app's language). */
function ridingWord(x) {
  if (x.word === "queue") return t("In queue");
  if (x.word === "squeeze") return t("Compressing");
  if (x.word?.startsWith("squeeze ")) return `${t("Compressing")} ${x.word.slice(8)}%`;
  return `${Math.floor(x.share * 100)}%`;
}
/** THE COMPACT PROGRESS PILL (iOS MessageBubble.progressPill): the ring, the word or the share, the cross -- a capsule of black
 *  0.6; the arc follows the share in 0.3 s. A tap on a riding letter does nothing (iOS: «stopping is an explicit act -- delete the
 *  bubble»). */
function RidingPill({ x }) {
  const r = 8, c = 2 * Math.PI * r, p = Math.max(0, Math.min(1, x.share));
  return (
    <span className="ride-pill" role="progressbar" aria-valuenow={Math.floor(p * 100)} aria-label={ridingWord(x)}>
      <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
        <circle cx="9" cy="9" r={r} fill="none" stroke="rgba(255,255,255,0.35)" strokeWidth="2" />
        <circle className="ride-arc" cx="9" cy="9" r={r} fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round"
                strokeDasharray={c} strokeDashoffset={c * (1 - p)} transform="rotate(-90 9 9)" />
      </svg>
      <span className="ride-word">{ridingWord(x)}</span>
      <span className="ride-cross" aria-hidden="true"><Glyph name="close" size={10} color="#fff" /></span>
    </span>
  );
}
/** On a plate: the pill top-left over a dim of black 0.2 (iOS mediaProgressOverlay); the tap stays here. */
const RidingDim = ({ x }) => (x ? <div className="ride-dim" onClick={(e) => e.stopPropagation()}><RidingPill x={x} /></div> : null);

/** A LETTER'S FILE IN THE FEED (iOS MediaBubble): a picture at its shape, a film behind its poster, a voice with its player,
 *  a file as a plate that opens it. Until the file is here the thumbnail stands; a file no store holds is «Not received». */
/** THE VOICE'S WAVE (iOS MTWaveform): sixty probes across the file -- the mean of every eighth sample of 4096 frames at each --
 *  scaled to a loud probe (the 92nd of a hundred), not the single loudest, and lifted on a soft curve (0.7); read once a voice. */
const WAVES = new Map();
async function waveOf(mid) {
  if (WAVES.has(mid)) return WAVES.get(mid);
  const ctx = new OfflineAudioContext(1, 1, 44100);
  const bytes = await invoke("media_get", { mid });   // the voice's own bytes (a blob's address is not the window's to fetch)
  const buf = await ctx.decodeAudioData(bytes instanceof ArrayBuffer ? bytes : new Uint8Array(bytes).buffer);
  const ch = buf.getChannelData(0), total = ch.length, raw = [];
  for (let i = 0; i < 60; i++) {
    const at = Math.floor((total * i) / 60);
    let acc = 0, n = 0;
    for (let j = at; j < Math.min(total, at + 4096); j += 8) { acc += Math.abs(ch[j]); n++; }
    raw.push(n ? acc / n : 0);
  }
  const ref = Math.max([...raw].sort((a, b) => a - b)[Math.floor(59 * 0.92)], 1e-6);
  const wave = raw.map((x) => Math.pow(Math.min(1, x / ref), 0.7));
  WAVES.set(mid, wave);
  return wave;
}
/** The wave drawn (iOS MTVoiceWaveShape): bars of 2 at a pitch of 4, at least 2 tall, centred in 28. */
function WaveBars({ wave, bars, width, fill, opacity }) {
  const step = width / bars;
  return Array.from({ length: bars }, (_, i) => {
    const amp = wave?.length ? wave[Math.min(wave.length - 1, Math.floor((i * wave.length) / bars))] : 0.12;
    const h = Math.max(2, 2 + amp * 26);
    return <rect key={i} x={i * step} y={(28 - h) / 2} width={2} height={h} rx={1} fill={fill} opacity={opacity} />;
  });
}
/** THE VOICE'S CAPSULE (iOS MessageBubble's voice): the play on its round of glass, the wave -- bright to the share played or chosen by
 *  the finger -- and the time: the length at rest, the place while it plays or is held; the capsule's width grows with the seconds to
 *  four fifths of the window. The whole capsule plays the voice, with the chat's voices behind it in feed order (onVoice); the
 *  finger's place on the wave starts it there. Under it the microphone with the length. */
function Voice({ m, o, url, onVoice, want }) {
  const f = player.usePlayer();
  const on = f.voice && f.file === m.mid;
  const c = player.useClock(on);
  const [wave, setWave] = useState(() => WAVES.get(m.mid) || null);
  const [held, setHeld] = useState(null);
  const [room, setRoom] = useState(window.innerWidth);
  const box = useRef(null);
  useEffect(() => {
    if (!url || wave) return;
    waveOf(m.mid).then((w) => { setWave(w); invoke("trace", { line: `voice wave read bars=${w.length}` }).catch(() => {}); })
      .catch((e) => invoke("trace", { line: `voice wave unreadable ${String(e?.name || e).slice(0, 40)}` }).catch(() => {}));
  }, [url]);
  useEffect(() => { setRoom(box.current?.closest(".feed")?.clientWidth || window.innerWidth); }, []);
  const length = o.du || (on ? c.of || f.duration : 0);
  const share = held ?? (on && (c.of || f.duration) > 0 ? c.at / (c.of || f.duration) : 0);
  const moving = on || held != null;
  const width = Math.min(Math.max(76, room * 0.8 - 111), Math.max(76, 60 + length * 8));
  const bars = Math.max(8, Math.floor(width / 4));
  const ink = m.mine ? "rgb(158, 222, 255)" : "#fff";
  const play = (at) => {
    if (!m.file) return want();
    if (on && !f.paused && at == null) return player.pause();
    if (on && at != null) return player.seek(at);
    onVoice?.(at);
  };
  const pos = (e) => Math.max(0, Math.min(1, (e.clientX - e.currentTarget.getBoundingClientRect().left) / width));
  return (
    <>
      <div className="voice-capsule" ref={box} role="button" tabIndex={0} aria-label={`${t("Voice message")} ${duration(length)}`}
           onClick={(e) => { if (!onVoice) return; e.stopPropagation(); play(); }} onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); play(); } }}>
        <span className="voice-round" aria-hidden="true">
          <Glyph name={!m.file ? "download" : on && !f.paused ? "pauseFill" : "playFill"} size={16} color="#fff" />
        </span>
        <svg className="voice-wave" width={width} height={28} aria-hidden="true"
             onPointerDown={(e) => { if (!m.file) return; e.stopPropagation(); e.currentTarget.setPointerCapture?.(e.pointerId); setHeld(pos(e)); }}
             onPointerMove={(e) => { if (held != null) setHeld(pos(e)); }}
             onPointerUp={(e) => { if (held == null) return; e.stopPropagation(); const at = pos(e); setHeld(null); play(at); }}
             onClick={(e) => e.stopPropagation()}>
          <WaveBars wave={wave} bars={bars} width={width} fill={ink} opacity={moving ? 0.4 : 0.9} />
          {moving && (
            <>
              <defs><clipPath id={`played-${m.mid}`}><rect x={0} y={0} width={width * Math.max(0, Math.min(1, share))} height={28} /></clipPath></defs>
              <g clipPath={`url(#played-${m.mid})`}><WaveBars wave={wave} bars={bars} width={width} fill={ink} opacity={1} /></g>
            </>
          )}
        </svg>
        <span className="voice-time digits">{duration(moving ? length * share : length) || "0:00"}</span>
      </div>
      <span className="voice-pill"><Glyph name="mic" size={10} color="#fff" /><span className="digits">{duration(length) || "0:00"}</span></span>
    </>
  );
}

export function MediaBody({ chat, m, onVoice, onPicture }) {
  const o = manifestOf(m.text);
  const url = useFile(m.mid, m.file, o.e, o.sz > BIG);
  const [playing, setPlaying] = useState(false);
  const thumb = o.th ? `data:image/jpeg;base64,${o.th}` : null;
  const waiting = !m.file && !m.gone && !m.mine;
  const status = m.gone ? <span className="media-status red">{t("Not received")}</span>
    : waiting ? <span className="media-status"><span className="spinner small" />{sizeText(o.sz)}</span> : null;
  const want = () => !m.file && !m.gone && invoke("media_want", { mid: m.mid });
  const riding = useRiding(m.mine ? m.mid : null);
  // A LOOK BRINGS IT BACK (iOS MTHomeKeep.want): a file this computer cleared and its owner's node keeps comes back when its bubble
  // stands here and the attachments download by themselves
  useEffect(() => { if (!m.file && !m.gone) invoke("media_look", { chat, mid: m.mid }).catch(() => {}); }, [m.mid, m.file]);
  // a film or a round note that is here is read once for its shape, for a check's diary (written only under MONTANA_TRACE)
  useEffect(() => {
    if (o.k !== "vid" || !url || NOTES_READ.has(m.mid + o.e + o.sz)) return;
    NOTES_READ.add(m.mid + o.e + o.sz);
    const what = `media ${o.r ? "note" : "film"} ${m.mine ? "mine" : "theirs"}`;
    const v = document.createElement("video");
    v.muted = true; v.preload = "metadata"; v.src = url;
    v.onloadedmetadata = () => invoke("trace", { line: `${what} ${v.videoWidth}x${v.videoHeight} ${o.e} ${o.sz ?? 0}` }).catch(() => {});
    v.onerror = () => invoke("trace", { line: `${what} unreadable` }).catch(() => {});
  }, [url]);

  if (o.k === "img") {
    return (
      // A PICTURE TAPPED OPENS AMONG THE CHAT'S PICTURES (iOS onTapImage -> PhotoPresenter.present(_:among:)); one not here yet asks
      // its file again instead of opening emptiness
      <div className="media-pic" role={url ? "button" : undefined} aria-label={url ? t("Photo") : undefined}
           onClick={() => (url && onPicture ? onPicture(m) : want())}>
        {url ? <img src={url} alt=""
                    onLoad={(e) => invoke("trace", { line: `media shows img ${o.e} ${e.target.naturalWidth}x${e.target.naturalHeight}` }).catch(() => {})} />
          : thumb ? <img src={thumb} alt="" className="blur" /> : <div className="media-blank"><Glyph name="photo" size={28} /></div>}
        {status}
        <RidingDim x={riding} />
      </div>
    );
  }
  if (o.k === "vid") {
    const plate = (
      <div className={"media-pic" + (o.r ? " round" : "")} onClick={() => (url ? setPlaying(true) : want())} role={o.r ? "button" : undefined}
           aria-label={o.r ? t("Video message") + (o.du ? " " + duration(o.du) : "") : undefined}>
        {playing && url ? <video src={url} controls autoPlay onEnded={() => setPlaying(false)} />
          : <>
              {thumb ? <img src={thumb} alt="" className={url ? "" : "blur"} /> : <div className="media-blank" />}
              {url && !riding && <span className="play">▶</span>}
            </>}
        {status}
        {!o.r && <RidingDim x={riding} />}
      </div>
    );
    // the round note's circle is never dimmed: its pill stands in the line beneath, bottom-left (iOS, the author's word 21.09)
    return o.r && riding ? <>{plate}<div className="ride-line"><RidingPill x={riding} /></div></> : plate;
  }
  if (o.k === "aud") {
    return (
      <>
        <Voice m={m} o={o} url={url} onVoice={onVoice} want={want} />
        {status}
        {riding && <RidingPill x={riding} />}
      </>
    );
  }
  // A MOVING PICTURE OR A STICKER OF THE HOUSE (iOS: the name says which, gif_ / stick_): drawn moving, the sticker bare
  if (o.k === "doc" && GIF_NAME.test(o.n || "")) {
    const sticker = o.n.toLowerCase().startsWith("stick_");
    return (
      <div className={"media-pic gif" + (sticker ? " bare" : "")} onClick={want} role="img" aria-label={sticker ? t("Sticker") : t("GIF")}>
        {url ? <img src={url} alt="" /> : <div className="media-blank" />}
        {status}
        <RidingDim x={riding} />
      </div>
    );
  }
  // a file: the plate, its name and size; a tap opens it (or asks for it). On its way: the ring over its icon, «N% · word» for
  // its size (iOS: «the same visibility as video: percentages and a status word»)
  const ring = riding && 2 * Math.PI * 15;
  return (
    <button className="media-doc" onClick={() => (riding ? null : m.file || m.mine ? invoke("media_open", { chat, mid: m.mid }) : want())}>
      <span className="media-doc-icon"><Glyph name="doc" size={22} />
        {riding && (
          <svg className="ride-doc" width="36" height="36" viewBox="0 0 36 36" aria-hidden="true">
            <circle cx="18" cy="18" r="18" fill="rgba(0,0,0,0.45)" />
            <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(255,255,255,0.35)" strokeWidth="3" />
            <circle className="ride-arc" cx="18" cy="18" r="15" fill="none" stroke="#fff" strokeWidth="3" strokeLinecap="round"
                    strokeDasharray={ring} strokeDashoffset={ring * (1 - Math.max(0, Math.min(1, riding.share)))} transform="rotate(-90 18 18)" />
          </svg>
        )}
      </span>
      <span className="media-doc-words">
        <span className="media-doc-name">{o.n && o.n !== "montana-card" ? o.n : t("File")}</span>
        {riding
          ? <span className="media-doc-size ride-doc-word" role="progressbar" aria-valuenow={Math.floor(riding.share * 100)}>
              {`${Math.floor(riding.share * 100)}%` + (riding.word ? " · " + ridingWord(riding) : "")}</span>
          : <span className="media-doc-size">{sizeText(o.sz)}{m.gone ? " · " + t("Not received") : ""}</span>}
      </span>
      {waiting && <span className="spinner small" />}
    </button>
  );
}

/** A picture made ready the way iOS sends one (MontanaMediaKit 984-1001): the long side at most 1600, JPEG 0.85, no EXIF (a
 *  GIF goes untouched); and its thumbnail: the long side 96, JPEG of at most 1200 bytes, the quality stepping down. */
async function canvasOf(src, side) {
  const img = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = no; i.src = src; });
  const k = Math.min(1, side / Math.max(img.naturalWidth, img.naturalHeight));
  const c = document.createElement("canvas");
  c.width = Math.max(1, Math.round(img.naturalWidth * k));
  c.height = Math.max(1, Math.round(img.naturalHeight * k));
  const g = c.getContext("2d");
  g.fillStyle = "#fff"; g.fillRect(0, 0, c.width, c.height);   // a transparent picture on white, as a JPEG holds it
  g.drawImage(img, 0, 0, c.width, c.height);
  return c;
}
const blobOf = (c, q) => new Promise((ok) => c.toBlob(ok, "image/jpeg", q));
const b64Of = async (blob) => {
  const b = new Uint8Array(await blob.arrayBuffer());
  let s = "";
  for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000));
  return btoa(s);
};
async function thumbOf(src, side, limit) {
  const c = await canvasOf(src, side);
  for (let q = 0.6; q >= 0.2; q -= 0.1) {
    const b = await blobOf(c, q);
    if (b.size <= limit) return b64Of(b);
  }
  return null;
}

/** A film's poster (iOS: the first frame, the long side 320, at most 12000 bytes), or nothing if the film will not show one. */
function posterOf(url) {
  return new Promise((ok) => {
    const v = document.createElement("video");
    const done = (x) => { clearTimeout(timer); ok(x); };
    const timer = setTimeout(() => done(null), 4000);
    v.muted = true; v.preload = "auto"; v.src = url;
    v.onloadeddata = () => { v.currentTime = Math.min(0.1, v.duration || 0); };
    v.onseeked = async () => {
      const c = document.createElement("canvas");
      const k = Math.min(1, 320 / Math.max(v.videoWidth, v.videoHeight));
      c.width = Math.round(v.videoWidth * k); c.height = Math.round(v.videoHeight * k);
      c.getContext("2d").drawImage(v, 0, 0, c.width, c.height);
      for (let q = 0.6; q >= 0.2; q -= 0.1) {
        const b = await blobOf(c, q);
        if (b && b.size <= 12000) return done({ th: await b64Of(b), du: v.duration });
      }
      done({ du: v.duration });
    };
    v.onerror = () => done(null);
  });
}

/** A FILE SENT (iOS ChatStore.sendMedia): made ready by its kind, then handed raw to the postman -- a 4-byte length, the
 *  manifest's fields, the bytes; a file larger than 200 MB is never read whole (sendBig). */
export async function sendFile(chat, file, caption, quote, extra = {}, onShare) {
  const ext = (file.name.split(".").pop() || "").toLowerCase();
  const meta = { chat, k: "doc", e: ext || "bin", n: file.name, cap: caption || undefined, qt: quote?.qt, qm: quote?.qm };
  let bytes = null;
  // a HEIC from an iPhone the window cannot open: Windows' own imaging gives it as PNG, and it goes as iOS sends a photo
  const png = await heifPng(file);
  const url = URL.createObjectURL(png ? new Blob([png], { type: "image/png" }) : file);
  try {
    if (png || (file.type.startsWith("image/") && !["svg+xml"].includes(file.type.slice(6)))) {
      meta.k = "img"; delete meta.n;
      if (file.type === "image/gif") {
        meta.e = "gif";
      } else {
        const c = await canvasOf(url, 1600);
        bytes = new Uint8Array(await (await blobOf(c, 0.85)).arrayBuffer());
        meta.e = "jpg";
      }
      meta.th = (await thumbOf(url, 96, 1200)) || undefined;
    } else if (file.type.startsWith("video/")) {
      meta.k = "vid"; delete meta.n;
      const p = await posterOf(url);
      if (p?.th) meta.th = p.th;
      if (Number.isFinite(p?.du) && p.du > 0) meta.du = p.du;
    }
  } catch { /* a picture the window cannot read goes as a file */
    meta.k = "doc"; meta.n = file.name;
  } finally {
    URL.revokeObjectURL(url);
  }
  // what the sender knows of the letter beyond its file: a round note's roundness and seconds, a call recording's kind
  if (meta.k !== "doc" || extra.k) Object.assign(meta, extra);
  invoke("trace", { line: `media send ${meta.k} ${meta.e}${png ? " from heif" : ""}` }).catch(() => {});
  if (!bytes && file.size > BIG) return sendBig(chat, file, meta, onShare);
  bytes = bytes || new Uint8Array(await file.arrayBuffer());
  const head = new TextEncoder().encode(JSON.stringify(meta));
  const body = new Uint8Array(4 + head.length + bytes.length);
  new DataView(body.buffer).setUint32(0, head.length, true);
  body.set(head, 4);
  body.set(bytes, 4 + head.length);
  return invoke("chat_send_media", body);
}

/** A FILE LARGER THAN 200 MB (iOS MediaSource.file): never read whole -- handed eight pieces of 512 KiB at a time, each kept
 *  sealed as it comes; the letter stands once every piece is kept. `onShare` hears the share handed, 0..100. */
async function sendBig(chat, file, meta, onShare) {
  const mid = await invoke("chat_big_begin", { chat });
  const step = 8 * PIECE;
  for (let at = 0; at < file.size; at += step) {
    const stretch = new Uint8Array(await file.slice(at, at + step).arrayBuffer());
    await invoke("chat_big_piece", stretch, { headers: { mid, index: String(at / PIECE) } });
    onShare?.(Math.floor(((at + stretch.length) / file.size) * 100));
  }
  return invoke("chat_big_end", { chat, mid, size: file.size, meta });
}
