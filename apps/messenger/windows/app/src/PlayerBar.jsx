import { useLayoutEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import * as player from "./player.js";
import { PlayerHead, QueuePage, TrackGlyph } from "./PlayerHead.jsx";

/** m:ss of seconds (iOS fmtDuration). */
export const clock = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
const SIDE = 64;   // the room of «-mm:ss» or «1.5×» with its side padding (iOS MTPlayerPlate.sideW)

/** A RUNNING LINE (iOS MTMarquee, MTMarqueeView): a name longer than its room scrolls past it once -- 1.2 s of waiting, one pass at
 *  30 points a second with the name again 48 behind, then it stands at its start and rests a minute before the next pass; a name
 *  that fits never moves (centred where its plate centres it). The pass is the compositor's (Web Animations), not a timer. */
export function Marquee({ text, className = "", centred = false }) {
  const box = useRef(null), strip = useRef(null), probe = useRef(null);
  const [runs, setRuns] = useState(false);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return undefined;
    let anim = null;
    const lay = () => {
      anim?.cancel(); anim = null;
      const room = el.clientWidth, w = Math.ceil(probe.current?.scrollWidth || 0);
      const run = room > 1 && w > room + 1;
      setRuns(run);
      if (!run || !strip.current?.animate) return;
      invoke("trace", { line: `marquee runs w=${w} room=${room}` }).catch(() => {});
      const travel = w + 48, wait = 1.2, pass = travel / 30, whole = wait + pass + 60, end = (wait + pass) / whole;
      anim = strip.current.animate([
        { transform: "translateX(0)", offset: 0 }, { transform: "translateX(0)", offset: wait / whole },
        { transform: `translateX(${-travel}px)`, offset: end }, { transform: "translateX(0)", offset: end }, { transform: "translateX(0)", offset: 1 },
      ], { duration: whole * 1000, iterations: Infinity, easing: "linear" });
    };
    lay();
    const ro = typeof ResizeObserver !== "undefined" ? new ResizeObserver(lay) : null;
    ro?.observe(el);
    return () => { ro?.disconnect(); anim?.cancel(); };
  }, [text]);
  return (
    <span ref={box} className={"marquee " + className + (centred && !runs ? " centred" : "")}>
      <span ref={strip} className="marquee-strip">
        <span ref={probe}>{text}</span>
        {runs && <span className="marquee-again" aria-hidden="true">{text}</span>}
      </span>
    </span>
  );
}

/** THE PLATE THAT IS THE SCRUBBER (iOS MTPlayerPlate): the bar's capsule fills with a transparent grey as the file plays; a stroke
 *  anywhere on it takes the place, the player asked once at the release; a tap in the side room at its right is the side's (the
 *  timer's face, the speed), a tap anywhere else the host's; a hold copies the name (copies). The name stands centred inside it. */
function Plate({ title, live, side, onSeek, onSide, onOpen, copies, still }) {
  const [held, setHeld] = useState(null);
  const [copied, setCopied] = useState(false);
  const touch = useRef(null);
  const p = held ?? live;
  const at = (e) => { const r = e.currentTarget.getBoundingClientRect(); return { x: e.clientX - r.left, w: r.width }; };
  const down = (e) => {
    if (still) return;
    const { x, w } = at(e);
    e.currentTarget.setPointerCapture?.(e.pointerId);
    const hold = copies ? setTimeout(() => {   // THE HOLD COPIES THE NAME (iOS MTNameCopy), at the chat's own threshold
      touch.current = null;
      invoke("copy_text", { text: title }).catch(() => {});
      invoke("trace", { line: "music mini title copied" }).catch(() => {});
      setCopied(true); setTimeout(() => setCopied(false), 2000);
    }, 220) : null;
    touch.current = { x0: x, moved: false, hold };
  };
  const move = (e) => {
    const tc = touch.current;
    if (!tc) return;
    const { x, w } = at(e);
    if (!tc.moved && Math.abs(x - tc.x0) < 6) return;
    tc.moved = true; clearTimeout(tc.hold);
    setHeld(Math.max(0, Math.min(1, x / w)));
  };
  const up = (e) => {
    const tc = touch.current;
    touch.current = null;
    if (!tc) return;
    clearTimeout(tc.hold);
    const { x, w } = at(e);
    if (tc.moved) { onSeek(Math.max(0, Math.min(1, x / w))); setHeld(null); return; }
    if (x >= w - SIDE) onSide(); else onOpen();
  };
  return (
    <div className={"mini-plate" + (still ? " still" : "")} role={still ? undefined : "slider"} aria-label={title} aria-valuemin={0} aria-valuemax={100}
         aria-valuenow={Math.round(p * 100)} aria-valuetext={side(p)} tabIndex={still ? -1 : 0}
         onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={() => { clearTimeout(touch.current?.hold); touch.current = null; setHeld(null); }}
         onKeyDown={(e) => { if (e.key === "ArrowRight") onSeek(Math.min(1, live + 0.05)); if (e.key === "ArrowLeft") onSeek(Math.max(0, live - 0.05)); }}>
      <span className="mini-fill" style={{ width: `${p * 100}%`, transition: held == null ? "width 0.25s linear" : "none" }} aria-hidden="true" />
      {copied || still ? <span className="mini-name">{copied ? t("Copied") : title}</span> : <Marquee text={title} className="mini-name" centred />}
      <span className="mini-side digits">{side(p)}</span>
    </div>
  );
}

/** THE ONE MINI PLAYER'S FACE (iOS MTMiniFace): as tall as the message field, in the bar's own dress -- the play, the track before,
 *  the plate that is the scrubber, the track after, the close; the thin blue ring on every button of the track that plays. */
export function MiniFace({ paused, title, live, side, onPlay, onSeek, onSide, onOpen, onClose, onPrev, onNext, ring, busy, cloud, copies, still }) {
  const r = ring ? " ringed" : "";
  return (
    <div className="mini-face">
      <button className={"glass-mark small mini-key" + r} onClick={onPlay} tabIndex={still ? -1 : 0}
              aria-label={busy ? t("Loading…") : cloud ? t("Download") : paused ? t("Play") : t("Pause")}>
        {busy ? <span className="spinner small" /> : <Glyph name={cloud ? "download" : paused ? "playFill" : "pauseFill"} size={cloud ? 17 : 18} color="var(--bar-glyph)" />}
      </button>
      {onPrev && <button className={"glass-mark small mini-key square" + r} onClick={onPrev} aria-label={t("Previous track")}><TrackGlyph back color="var(--bar-glyph)" /></button>}
      <div className={"mini-plate-ring" + r}>
        <Plate title={title} live={live} side={side} onSeek={onSeek} onSide={onSide} onOpen={onOpen} copies={copies} still={still} />
      </div>
      {onNext && <button className={"glass-mark small mini-key square" + r} onClick={onNext} aria-label={t("Next track")}><TrackGlyph color="var(--bar-glyph)" /></button>}
      {onClose && <button className={"glass-mark small mini-key" + r} onClick={onClose} aria-label={t("Close")}><Glyph name="close" size={16} color="var(--bar-glyph)" /></button>}
    </div>
  );
}

/** THE ONE FLOATING PLAYER OF THE PAGES (iOS MontanaPlayerBar): it stands while the player holds a track or a voice, over the rows'
 *  bottom on the chats and the music, over the feed above the message field, at the foot of a correspondent's page. A track shows
 *  its timer (its two faces, a tap on it turns them, kept across launches) and the track before and after; a voice its sender and
 *  its speed. A tap on the name: a track goes to its place on the music page (onPlace), a voice to its letter (onGoTo). */
export function PlayerBar({
  row = false,
  onPlace = (track) => window.dispatchEvent(new CustomEvent("montana-music-show", { detail: track?.file })),
  onGoTo = (chat, mid) => window.dispatchEvent(new CustomEvent("montana-show-letter", { detail: { chat, mid } })),
}) {
  const f = player.usePlayer();
  const c = player.useClock(!!f.file);
  const [remaining, setRemaining] = useState(() => { try { return localStorage.getItem("miniTimeRemaining") === "1"; } catch { return false; } });
  const [queue, setQueue] = useState(false);
  const [folding, setFolding] = useState(false);
  player.useMeta(f.voice ? null : f.track);   // every hook before the bar's first way out: the count of hooks never changes
  if (!f.file || (row && f.voice)) return null;   // the list's standing row is the track's, whatever else plays over it
  const track = !f.voice;
  // THE MINI UNFOLDS WHERE IT STANDS (iOS MTPlayerHead, its spring 0.36 s at 0.88): the same bar, the same place over the rows; it rises
  // from nine tenths of its size at its foot and fades in, and folds back the same way at a tap on its name
  if (!row && track && f.unfold) {
    const fold = () => { if (folding) return; setFolding(true); setTimeout(() => { setFolding(false); player.setUnfold(false); }, 260); };
    return (
      <div className={"player-bar unfolded" + (folding ? " folding" : "")} role="region" aria-label={t("Player")}>
        <PlayerHead onFold={fold} onQueue={() => setQueue(true)}
                    onSearch={() => window.dispatchEvent(new CustomEvent("montana-music-search"))} />
        {queue && <QueuePage onClose={() => setQueue(false)} onPlace={() => onPlace(f.track)} />}
      </div>
    );
  }
  const of = c.of || f.duration;
  const live = of > 0 ? Math.max(0, Math.min(1, c.at / of)) : 0;
  const side = (p) => (track ? (remaining ? "-" + clock(Math.max(0, of - p * of)) : clock(p * of)) : f.rate === 1 ? "1×" : f.rate === 2 ? "2×" : "1.5×");
  return (
    <div className="player-bar" role="region" aria-label={t("Player")}>
      <MiniFace paused={f.paused} title={(track ? player.nameOf(f.track) : f.title) || (f.voice ? t("Voice message") : "")} live={live} side={side} ring copies
                onPlay={() => { invoke("trace", { line: `music mini play by=bar to=${f.paused ? "on" : "rest"}` }).catch(() => {}); player.toggle(); }}
                onSeek={player.seek}
                onSide={() => {
                  if (!track) return player.turnRate();
                  setRemaining((r) => { try { localStorage.setItem("miniTimeRemaining", r ? "0" : "1"); } catch { /* this run */ } return !r; });
                }}
                onOpen={() => (track ? player.setUnfold(true) : onGoTo?.(f.chat, f.mid))}
                onClose={row ? null : player.stop}
                onPrev={track && !row ? () => { invoke("trace", { line: "music mini prev" }).catch(() => {}); player.prev(); } : null}
                onNext={track && !row ? () => { invoke("trace", { line: "music mini next" }).catch(() => {}); player.next(); } : null} />
    </div>
  );
}

/** THE ROW IS THE MINI'S FACE (iOS MTTrackRow.face): its play, its name in the plate, its length at the plate's end; the track that
 *  plays wears the thin blue ring. The whole row is one target -- nothing inside answers a second time. */
export function TrackRow({ title, length, playing, paused, busy, cloud, onTap, label }) {
  return (
    <div className="track-row" role="button" tabIndex={0} onClick={onTap} aria-label={label || (length > 0 ? `${title}, ${clock(length)}` : title)}
         aria-current={playing ? "true" : undefined}
         onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onTap(); } }}>
      <div aria-hidden="true">
        <MiniFace still paused={!(playing && !paused)} title={title} live={0} side={() => (length > 0 ? clock(length) : "")}
                  onPlay={() => {}} onSeek={() => {}} onSide={() => {}} onOpen={() => {}} ring={playing} busy={busy} cloud={cloud} />
      </div>
    </div>
  );
}

/** The room a list keeps at its foot while the bar floats over it (iOS playerReserve). */
export function usePlayerReserve() {
  const f = player.usePlayer();
  return f.file ? 52 : 0;
}
