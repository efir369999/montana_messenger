import { Children, createContext, useContext, useEffect, useLayoutEffect, useRef, useState } from "react";
import { useLeave } from "./leave.js";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { keptPictures } from "./caches.js";
import { Glyph } from "./TopBar.jsx";
import { sizeText } from "./Media.jsx";
import * as player from "./player.js";
import { stem } from "./player.js";
import { PlayerBar, TrackRow as MiniRow } from "./PlayerBar.jsx";

/** THE FILES OF A POST (iOS MTBoardMediaView, MTBoardMosaic, MTBoardPicture, MTBoardMediaPage): pictures and films as tiles of a
 *  mosaic, each in the shape its writer gave it; tracks and files as rows under them. */

/** A file's kind in a post, by its extension (iOS MTPostMeasure.kind, mtIsAudioName). */
export function postKind(name) {
  const e = (String(name).split(".").pop() || "").toLowerCase();
  if (["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].includes(e)) return "img";
  if (["mov", "mp4", "m4v"].includes(e)) return "vid";
  if (["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "caf"].includes(e)) return "aud";
  return "doc";
}
/** The files a post takes (iOS MTPostMeasure.files) and a picture's shapes, width over height, 9:16 to 16:9 (iOS MTBoardFrame). */
export const POST_FILES = 10;
export const held = (a) => (Number.isFinite(a) && a > 0 ? Math.min(Math.max(a, 9 / 16), 16 / 9) : 1);
export const visual = (m) => m.kind === "img" || m.kind === "vid";

/** The rows of a mosaic (iOS MTBoardMosaic.rows): an odd one first across the whole width, then two by two. */
export function mosaicRows(n) {
  const out = [];
  let i = 0;
  if (n % 2 === 1) { out.push([0]); i = 1; }
  while (i + 1 < n) { out.push([i, i + 1]); i += 2; }
  return out;
}
/** Each tile's frame in a mosaic of this width (iOS MTBoardMosaic.frames): every row fills the width, every tile keeps its shape. */
export function mosaicFrames(shapes, width, gap = 4) {
  const out = [];
  let y = 0;
  for (const row of mosaicRows(shapes.length)) {
    const sum = row.reduce((s, i) => s + Math.max(0.1, shapes[i]), 0);
    const h = Math.floor((width - gap * (row.length - 1)) / sum);
    let x = 0;
    row.forEach((i, k) => {
      const w = k === row.length - 1 ? width - x : Math.round(h * Math.max(0.1, shapes[i]));
      out[i] = { x, y, w: Math.max(1, w), h: Math.max(1, h) };
      x += w + gap;
    });
    y += h + gap;
  }
  return out;
}

/** The mosaic itself: laid at its own width, measured as it changes. */
export function Mosaic({ shapes, children, gap = 4 }) {
  const box = useRef(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    setWidth(el.clientWidth);
    const ro = new ResizeObserver(() => setWidth(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const fs = mosaicFrames(shapes, width || 320, gap);
  const height = fs.reduce((m, f) => Math.max(m, f.y + f.h), 0);
  return (
    <div ref={box} className="mosaic" style={{ height }}>
      {Children.toArray(children).map((c, i) => fs[i] && (
        <div key={i} className="mosaic-cell" style={{ left: fs[i].x, top: fs[i].y, width: fs[i].w, height: fs[i].h }}>{c}</div>
      ))}
    </div>
  );
}

/** The part of a picture its frame shows, drawn over its tile (iOS MTBoardImage.cut): the picture scaled so the frame fills the tile. */
export function framed(fr) {
  if (!fr || !(fr.w > 0) || !(fr.h > 0)) return { width: "100%", height: "100%", left: 0, top: 0, objectFit: "cover" };
  return { width: `${100 / fr.w}%`, height: `${100 / fr.h}%`, left: `${(-fr.x / fr.w) * 100}%`, top: `${(-fr.y / fr.h) * 100}%` };
}

const MIME = { jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", gif: "image/gif", webp: "image/webp", mp4: "video/mp4",
               m4v: "video/mp4", mov: "video/mp4", mp3: "audio/mpeg", m4a: "audio/mp4", aac: "audio/aac", wav: "audio/wav",
               flac: "audio/flac", aif: "audio/aiff", aiff: "audio/aiff", caf: "audio/x-caf" };
/** A post's file as an address the window can draw or play, brought from the node once (Rust wall_file), kept while the window lives. */
const files = keptPictures(new Map());
export function useWallFile(wall, post, index, m, want = true) {
  const key = `${wall || ""}/${post.id}/${index}`;
  const [url, setUrl] = useState(files.get(key) || null);
  useEffect(() => {
    if (!want || files.has(key)) { setUrl(files.get(key) || null); return; }
    let live = true;
    invoke("wall_file", { wall, id: post.id, index }).then((buf) => {
      const u = URL.createObjectURL(new Blob([buf], { type: MIME[(m.ext || "").toLowerCase()] || "application/octet-stream" }));
      files.set(key, u);
      if (live) setUrl(u);
    }).catch(() => {});
    return () => { live = false; };
  }, [key, want]);
  return url;
}

/** A TILE OF A POST (iOS MTBoardMediaView.tile, MTBoardPicture, MTBoardClip): the poster the post carries at once, the file itself
 *  when it came; a film behind its poster with the play glyph -- a touch opens the viewer of the post's pictures and films. */
function Tile({ wall, post, index, m, onShow, draft }) {
  const isVid = m.kind === "vid";
  // a picture is brought to be seen (iOS MTBoardLook); a film waits for a touch; a post being written draws its posters alone
  const url = useWallFile(wall, post, index, m, !isVid && !draft);
  const poster = m.thumb ? `data:image/jpeg;base64,${m.thumb}` : null;
  return (
    <button className="post-tile" aria-label={t(isVid ? "Video" : "Photo")} onClick={(e) => { e.stopPropagation(); onShow?.(index); }}>
      {url ? <img src={url} alt="" draggable={false} style={framed(m.fr)}
                  onLoad={(e) => invoke("trace", { line: `wall picture file ${e.target.naturalWidth}x${e.target.naturalHeight}` }).catch(() => {})} />
        : poster ? <img src={poster} alt="" draggable={false} style={framed(null)} /> : null}
      {isVid && <span className="post-tile-play" aria-hidden="true"><PlayCircle /></span>}
    </button>
  );
}
/** SF «play.circle.fill» 30, white at 90 %. */
function PlayCircle({ side = 30 }) {
  return (
    <svg width={side} height={side} viewBox="0 0 30 30" aria-hidden="true">
      <circle cx="15" cy="15" r="15" fill="rgba(255,255,255,0.9)" />
      <path d="M12 9.5v11l9-5.5z" fill="rgba(0,0,0,0.75)" />
    </svg>
  );
}

const length = (s) => (s > 0 ? `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}` : "");

/** A TRACK OF A POST IS A TRACK OF THE ONE PLAYER (iOS MTBoardMediaView.track, the author's word 24.09): the playing track wears the
 *  mini player itself (MontanaPlayerBar, row) and every other stands in the mini's face -- its play, its name in the plate, its
 *  length; the whole row is one target: a touch brings the track once and plays it, the post's tracks as the queue. */
/** THE PAGE'S TRACKS ARE THE QUEUE (iOS MTBoardPlaylist): a wall or the feed names every track of its posts, in their order, once. */
export const PageTracks = createContext(null);
const wallTrack = (wall, post, i, x) => ({ file: `wall:${wall || ""}/${post.id}/${i}`, wall: { wall, id: post.id, index: i }, ext: x.ext,
                                            title: stem(x.name) || x.name || t("Track") });
function TrackRow({ wall, post, index, m }) {
  const now = player.usePlayer();
  const page = useContext(PageTracks);
  const me = wallTrack(wall, post, index, m);
  if (!now.voice && now.file === me.file) return <div className="post-track-live" onClick={(e) => e.stopPropagation()}><PlayerBar row /></div>;
  const tracks = page?.some((x) => x.file === me.file) ? page
    : post.media.map((x, i) => [x, i]).filter(([x]) => x.kind === "aud").map(([x, i]) => wallTrack(wall, post, i, x));
  return (
    <div className="post-track-row" onClick={(e) => e.stopPropagation()}>
      <MiniRow title={me.title} length={m.dur} onTap={() => player.playQueue(tracks, tracks.findIndex((x) => x.file === me.file))} />
    </div>
  );
}

/** A FILE OF A POST (iOS MTBoardMediaView.fileRow): the doc in its grey square, the name without its extension, the size under it;
 *  a touch brings it and opens it where Windows opens such a file. */
function FileRow({ wall, post, index, m }) {
  const [busy, setBusy] = useState(false);
  const name = (m.name || "").replace(/\.[^.]+$/, "") || m.name;
  const open = async (e) => {
    e.stopPropagation();
    setBusy(true);
    try { await invoke("wall_open", { wall, id: post.id, index }); } catch { /* not brought: the row stays */ }
    setBusy(false);
  };
  return (
    <button className="post-file" aria-label={m.name} onClick={open}>
      <span className="post-file-icon"><Glyph name={m.kind === "aud" ? "musicNote" : "doc"} size={17} color="var(--gray)" /></span>
      <span className="post-file-words"><span className="post-file-name">{name}</span><span className="post-file-size">{sizeText(m.size)}</span></span>
      {busy && <span className="spinner small" />}
    </button>
  );
}

/** A track or a file of a post being written: its face as it will stand, nothing to press yet (iOS: allowsHitTesting(false)). */
function StillRow({ m }) {
  const name = (m.name || "").replace(/\.[^.]+$/, "") || m.name;
  return m.kind === "aud" ? (
    <div className="post-track" aria-hidden="true">
      <span className="post-track-play"><Glyph name="playFill" size={18} color="var(--bar-glyph)" /></span>
      <span className="post-track-plate"><span className="post-track-name">{name}</span><span className="post-track-side digits">{length(m.dur)}</span></span>
    </div>
  ) : (
    <div className="post-file" aria-hidden="true">
      <span className="post-file-icon"><Glyph name="doc" size={17} color="var(--gray)" /></span>
      <span className="post-file-words"><span className="post-file-name">{name}</span><span className="post-file-size">{sizeText(m.size)}</span></span>
    </div>
  );
}

/** THE FILES OF A POST (iOS MTBoardMediaView): the pictures and films in their mosaic, then the tracks and the files, 8 apart; a
 *  post being written (`draft`) draws them as they will stand, from their posters. */
export function PostMedia({ wall, post, onShow, draft }) {
  const md = post.media || [];
  const vis = md.map((m, i) => [m, i]).filter(([m]) => visual(m));
  const other = md.map((m, i) => [m, i]).filter(([m]) => !visual(m));
  if (!md.length) return null;
  return (
    <div className="post-media">
      {vis.length > 0 && (
        <Mosaic shapes={vis.map(([m]) => held(m.fr?.a))}>
          {vis.map(([m, i]) => <Tile key={i} wall={wall} post={post} index={i} m={m} onShow={draft ? null : onShow} draft={draft} />)}
        </Mosaic>
      )}
      {other.map(([m, i]) => (draft ? <StillRow key={i} m={m} />
        : m.kind === "aud" ? <TrackRow key={i} wall={wall} post={post} index={i} m={m} />
        : <FileRow key={i} wall={wall} post={post} index={i} m={m} />))}
    </div>
  );
}

/** THE VIEWER OF A POST'S PICTURES AND FILMS (iOS MTBoardMediaPage): one to a screen on black, the next and the one before by the
 *  wheel, the arrows or the marks; a film plays with its sound, the file brought whole and counted as a download (a touch). */
export function MediaShow({ wall, post, start, onClose }) {
  const items = (post.media || []).map((m, i) => [m, i]).filter(([m]) => visual(m));
  const [at, setAt] = useState(Math.max(0, items.findIndex(([, i]) => i === start)));
  const [url, setUrl] = useState(null);
  const [m, index] = items[at] || [];
  useEffect(() => {
    if (!m) return;
    let live = true, made = null;
    setUrl(null);
    invoke("wall_file", { wall, id: post.id, index, touch: m.kind === "vid" }).then((buf) => {
      made = URL.createObjectURL(new Blob([buf], { type: MIME[(m.ext || "").toLowerCase()] || "application/octet-stream" }));
      if (live) setUrl(made);
    }).catch(() => {});
    return () => { live = false; if (made && !files.has(`${wall || ""}/${post.id}/${index}`)) URL.revokeObjectURL(made); };
  }, [at]);
  useEffect(() => {
    const key = (e) => {
      if (e.key === "ArrowDown" || e.key === "ArrowRight") setAt((x) => Math.min(items.length - 1, x + 1));
      if (e.key === "ArrowUp" || e.key === "ArrowLeft") setAt((x) => Math.max(0, x - 1));
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [items.length]);
  useLeave(onClose);
  if (!m) return null;
  const poster = m.thumb ? `data:image/jpeg;base64,${m.thumb}` : null;
  return (
    <div className="media-show" role="dialog" aria-label={t(m.kind === "vid" ? "Video" : "Photo")} onClick={(e) => e.stopPropagation()}
         onWheel={(e) => setAt((x) => Math.max(0, Math.min(items.length - 1, x + (e.deltaY > 0 ? 1 : -1))))}>
      <div className="media-show-stage">
        {m.kind === "vid"
          ? (url ? <video key={url} src={url} controls autoPlay playsInline
                          onPlaying={() => invoke("trace", { line: `wall film plays ${m.ext}` }).catch(() => {})} />
                 : poster && <img src={poster} alt="" />)
          : <img src={url || poster || undefined} alt="" draggable={false} />}
        {!url && <span className="spinner" />}
      </div>
      <button className="glass-mark media-show-close" onClick={onClose} aria-label={t("Close")}><Glyph name="close" size={18} color="#fff" /></button>
      {items.length > 1 && <span className="media-show-count digits">{at + 1} / {items.length}</span>}
    </div>
  );
}

/** MY FACE, SMALL (iOS MTBoard.small: a square cut to fill it, JPEG 0.6): 96 over a post I write on another's wall (myFace), 64 over
 *  a comment (commentFace); nothing when I wear no photo. */
const faces = new Map();
export async function smallFace(side) {
  if (faces.has(side)) return faces.get(side);
  let out = null;
  try {
    const buf = await invoke("face_get", { chat: "" });
    if (buf && buf.byteLength) {
      const u = URL.createObjectURL(new Blob([buf], { type: "image/jpeg" }));
      try {
        const img = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = no; i.src = u; });
        const c = document.createElement("canvas");
        c.width = c.height = side;
        const k = Math.max(side / img.naturalWidth, side / img.naturalHeight);
        const w = img.naturalWidth * k, h = img.naturalHeight * k;
        c.getContext("2d").drawImage(img, (side - w) / 2, (side - h) / 2, w, h);
        out = c.toDataURL("image/jpeg", 0.6).split(",")[1] || null;
      } finally { URL.revokeObjectURL(u); }
    }
  } catch { /* no face of mine: the glyph stands */ }
  faces.set(side, out);
  return out;
}
export const forgetSmallFaces = () => faces.clear();
