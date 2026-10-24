import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import * as player from "./player.js";
import { clock, Marquee } from "./PlayerBar.jsx";
import iconPicture from "./assets/ios/AppIconPicture.png";

/** A TRACK'S COVER (iOS MTMusicCover): the track's own picture when its file carries one; the app's icon picture in its rounded
 *  square (0.2237 of its side) when it does not -- Windows reads no tags of a track, so every track wears the icon. */
export function Cover({ side, onClick, src, corner }) {
  const r = src ? corner ?? side * 0.18 : side * 0.2237;
  const img = <img src={src || iconPicture} alt="" width={side} height={side} draggable={false} style={{ borderRadius: r, display: "block", objectFit: "cover" }} />;
  return onClick ? <button className="cover-key" style={{ width: side, height: side, borderRadius: r }} onClick={onClick} aria-label={t("Cover")}>{img}</button> : img;
}

/** The sound's wave beside the name (iOS waveform, variableColor while it plays): five bars, rising one after another. */
function Waving({ on }) {
  return (
    <span className={"waving" + (on ? " on" : "")} aria-hidden="true">
      {[0.45, 0.8, 1, 0.7, 0.4].map((h, i) => <i key={i} style={{ height: `${h * 100}%`, animationDelay: `${i * 0.12}s` }} />)}
    </span>
  );
}

/** THE ONE VIEW OF THE BIG PLAYER THAT WATCHES THE CLOCK (iOS MTPlayerClockLine): the elapsed, the line of the time -- a capsule 7 tall
 *  in white 0.2, filled in white 0.72, the finger's 44 around it, the place taken by a stroke and asked once at the release -- and
 *  the remaining with a minus. */
function ClockLine() {
  const c = player.useClock(true);
  const [held, setHeld] = useState(null);
  const total = c.of;
  const p = held ?? (total > 0 ? Math.min(1, c.at / total) : 0);
  const at = (e) => { const r = e.currentTarget.getBoundingClientRect(); return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); };
  return (
    <div className="clock-line">
      <span className="digits">{clock(total * p)}</span>
      <div className="clock-track" role="slider" aria-label={t("Playback position")} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(p * 100)} tabIndex={0}
           onPointerDown={(e) => { e.currentTarget.setPointerCapture?.(e.pointerId); setHeld(at(e)); }}
           onPointerMove={(e) => { if (held != null) setHeld(at(e)); }}
           onPointerUp={(e) => { if (held == null) return; player.seek(at(e)); setHeld(null); }}
           onKeyDown={(e) => { if (e.key === "ArrowRight") player.seek(Math.min(1, p + 0.05)); if (e.key === "ArrowLeft") player.seek(Math.max(0, p - 0.05)); }}>
        <span className="clock-rail"><span className="clock-fill" style={{ width: `${p * 100}%`, transition: held == null ? "width 0.25s linear" : "none" }} /></span>
      </div>
      <span className="digits">-{clock(Math.max(0, total - total * p))}</span>
    </div>
  );
}

/** THE SOUND'S LINE (iOS MTVolumeLine): a thin floating scale between the quiet and the loud speaker, the whole 44 the finger's. The
 *  system's own volume on iOS; a page cannot move Windows' volume, so the line is the player's own share of it. */
function VolumeLine() {
  const [v, setV] = useState(player.volume());
  return (
    <div className="volume-line" aria-label={t("Volume")}>
      <SpeakerGlyph waves={0} />
      <input type="range" min={0} max={1} step={0.01} value={v} aria-label={t("Volume")}
             onChange={(e) => { const x = Number(e.target.value); setV(x); player.setVolume(x); }} />
      <SpeakerGlyph waves={3} />
    </div>
  );
}
const SpeakerGlyph = ({ waves }) => (
  <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true">
    <path d="M4 9h3l5-4v14l-5-4H4z" fill="var(--ink-2)" />
    {waves > 0 && <path d="M15 9a4 4 0 0 1 0 6M17.5 6.5a7.5 7.5 0 0 1 0 11M20 4a11 11 0 0 1 0 16" fill="none" stroke="var(--ink-2)" strokeWidth="1.8" strokeLinecap="round" />}
  </svg>
);

/** THE BIG PLAYER, THE MINI UNFOLDED WHERE IT STANDS (iOS MTPlayerHead): the plate on the glass -- the cover (a tap raises it over the
 *  plate), the name with what the player just did said under it, the sound's wave; the line of the time; the track before, the play
 *  and the track after at the middle, the playlist that plays at the left; the sound's line under the plate; the five round keys --
 *  the repeat and the shuffle lit while on, the music page's search, where it plays from, the share. A tap on the name folds it. */
export function PlayerHead({ onFold, onSearch, onQueue }) {
  const f = player.usePlayer();
  const [cover, setCover] = useState(false);
  const [lowering, setLowering] = useState(false);
  // THE COVER RISES OVER THE PLATE AND FOLDS BACK (iOS MTCoverStage, its spring 0.36 s at 0.86): from a seventh of its size at its
  // foot's left corner, fading in; back the same way
  const turnCover = () => {
    if (!cover) return setCover(true);
    if (lowering) return;
    setLowering(true);
    setTimeout(() => { setLowering(false); setCover(false); }, 260);
  };
  const [said, setSaid] = useState(null);
  const [choosing, setChoosing] = useState(false);
  const turn = useRef(0);
  const say = (text) => {
    const n = ++turn.current;
    setSaid(text);
    setTimeout(() => { if (turn.current === n) setSaid(null); }, 2000);
  };
  const sounding = !!f.file && !f.voice;
  const meta = player.useMeta(f.track);
  const name = player.nameOf(f.track) || f.title;
  return (
    <div className="player-head">
      {cover && (
        <button className={"cover-stage" + (lowering ? " lowering" : "")} onClick={turnCover} aria-label={t("Close")}>
          <img src={meta?.cover || iconPicture} alt="" draggable={false} />
        </button>
      )}
      <div className="head-plate">
        <div className="head-top">
          <Cover side={57} corner={10} src={meta?.cover} onClick={turnCover} />
          <div className="head-words" role="button" tabIndex={0} aria-label={name} onClick={onFold}
               onKeyDown={(e) => { if (e.key === "Enter") onFold(); }}>
            <Marquee text={name} className="head-title" />
            {said ? <span className="head-said">{said}</span> : meta?.artist && <span className="head-by">{meta.artist}</span>}
          </div>
          <Waving on={sounding && !f.paused} />
        </div>
        <ClockLine />
        <div className="head-controls">
          <button className="head-place" onClick={onQueue} aria-label={t("Current playlist")}>
            <ListNumber />{f.index >= 0 && <span className="digits">{f.index + 1}</span>}
          </button>
          <div className="head-three">
            <button className="head-control" onClick={player.prev} aria-label={t("Previous track")}><TrackGlyph back size={28} /></button>
            <button className="head-control big" onClick={player.toggle} aria-label={f.paused ? t("Play") : t("Pause")}>
              <Glyph name={f.paused ? "playFill" : "pauseFill"} size={36} color="var(--ink)" />
            </button>
            <button className="head-control" onClick={player.next} aria-label={t("Next track")}><TrackGlyph size={28} /></button>
          </div>
          <span className="head-place" aria-hidden="true" />
        </div>
      </div>
      <VolumeLine />
      <div className="head-keys">
        <button className={"glass-mark head-key" + (f.repeat !== "off" ? " lit" : "")} aria-label={t("Repeat")}
                onClick={() => { player.turnRepeat(); const r = player.face().repeat; say(t(r === "track" ? "Repeat track" : r === "all" ? "Repeat playlist" : "Repeat off")); }}>
          <RepeatGlyph one={f.repeat === "track"} />
        </button>
        <button className={"glass-mark head-key" + (f.shuffle ? " lit" : "")} aria-label={t("Shuffle")}
                onClick={() => { player.turnShuffle(); say(t(player.face().shuffle ? "Shuffle on" : "Shuffle off")); }}>
          <ShuffleGlyph />
        </button>
        <button className="glass-mark head-key" aria-label={t("Search")} onClick={onSearch}><SearchGlyph /></button>
        <div className="head-filter">
          <button className={"glass-mark head-key" + (f.source !== "all" ? " lit" : "")} aria-label={t("Source")} aria-expanded={choosing}
                  onClick={() => setChoosing(!choosing)}><FilterGlyph /></button>
          {choosing && <SourceMenu onClose={() => setChoosing(false)} />}
        </div>
        <button className="glass-mark head-key" aria-label={t("Share")} onClick={() => player.share()}><Glyph name="share" size={17} color="var(--ink)" /></button>
      </div>
    </div>
  );
}

/** WHERE IT PLAYS FROM (iOS the filter's menu, MTTrackSource): every track, the chats', the walls', the folders', or one chat's -- the
 *  chosen source's tracks become the queue; the track that plays keeps playing when the source holds it, else the source's first. */
function SourceMenu({ onClose }) {
  const f = player.usePlayer();
  const [chats, setChats] = useState([]);
  useEffect(() => { player.sourceChats().then(setChats).catch(() => {}); }, []);
  const pick = (s) => { onClose(); player.listen(s); };
  const row = (s, label) => (
    <button key={s} className="menu-row" role="menuitemradio" aria-checked={f.source === s} onClick={() => pick(s)}>
      <span>{label}</span>{f.source === s ? <Glyph name="check" size={16} /> : <span />}
    </button>
  );
  return (
    <div className="menu-shade" onClick={onClose}>
      <div className="letter-menu source-menu" role="menu" onClick={(e) => e.stopPropagation()}>
        <div className="menu-rows">
          {row("all", t("All"))}{row("chats", t("Chats"))}{row("walls", t("Walls"))}{row("folders", t("Folders"))}
          {chats.length > 1 && chats.map((c) => row(`chat:${c.id}`, c.title))}
        </div>
      </div>
    </div>
  );
}

/** THE QUEUE'S OWN PAGE (iOS MTQueuePage): «Playing from» the source, the track that plays in the middle in blue with its wave, the
 *  others by their place; a click plays, the cross takes one out; the order turned over by the arrows; the music page centred on the
 *  track by «Show in playlist». */
export function QueuePage({ onClose, onPlace }) {
  const f = player.usePlayer();
  const list = player.queue();
  const box = useRef(null);
  useEffect(() => {
    box.current?.querySelector(".queue-row.on")?.scrollIntoView({ block: "center" });
    invoke("trace", { line: `music_queue page n=${list.length} at=${f.index + 1}` }).catch(() => {});
  }, []);
  return (
    <div className="sheet-shade" onClick={onClose}>
      <div className="queue-page" role="dialog" aria-label={t("Now playing")} onClick={(e) => e.stopPropagation()}>
        <div className="queue-head">
          <button className="glass-mark" onClick={onClose} aria-label={t("Close")}><Glyph name="close" size={16} color="var(--bar-glyph)" /></button>
          <span className="queue-title">{t("Now playing")}</span>
          <button className="glass-mark" onClick={() => { onClose(); onPlace?.(); }} aria-label={t("Show in playlist")}><ListNumber /></button>
          <button className="glass-mark" onClick={player.reverseQueue} aria-label={t("Reverse order")}><ArrowsGlyph /></button>
        </div>
        <div className="queue-from">{t("Playing from %@").replace("%@", t(player.sourceName()))}</div>
        <div className="queue-rows" ref={box}>
          {list.map((x, i) => {
            const on = i === f.index;
            return <QueueRow key={x.file} x={x} i={i} on={on} paused={f.paused} />;
          })}
        </div>
      </div>
    </div>
  );
}

/** A ROW OF THE QUEUE (iOS MTQueuePage.row): the cover (44, 8), the tag's name -- in blue and bold while it plays -- with the artist
 *  under it, the wave while it plays, else its place; a click plays it, the cross takes it out. Its tags are read when it stands. */
function QueueRow({ x, i, on, paused }) {
  const m = player.useMeta(x);
  const name = m?.title || x.title;
  return (
    <div className={"queue-row" + (on ? " on" : "")}>
      <button className="queue-play" onClick={() => { invoke("trace", { line: `music_queue play i=${i + 1} by=queue-page` }).catch(() => {}); player.play(i); }}
              aria-label={m?.artist ? `${name}, ${m.artist}` : name}>
        <Cover side={44} corner={8} src={m?.cover} />
        <span className="queue-words"><span className="queue-name">{name}</span>{m?.artist && <span className="queue-by">{m.artist}</span>}</span>
        {on ? <Waving on={!paused} /> : <span className="queue-n digits">{i + 1}</span>}
      </button>
      <button className="queue-out" onClick={() => player.dropFromQueue(x.file)} aria-label={`${t("Remove")}: ${name}`}>
        <Glyph name="close" size={12} color="var(--gray)" />
      </button>
    </div>
  );
}

// the platform's glyphs the big player wears (SF Symbols: backward.fill, forward.fill, list.number, repeat, repeat.1, shuffle,
// magnifyingglass, line.3.horizontal.decrease, arrow.up.arrow.down), drawn at their shapes
export function TrackGlyph({ back, size = 20, color = "var(--ink)" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" style={{ transform: back ? "scaleX(-1)" : undefined }}>
      <path d="M3 6.2v11.6c0 .8.9 1.3 1.6.8L12 13.3v4.5c0 .8.9 1.3 1.6.8l8-5.8a1 1 0 0 0 0-1.6l-8-5.8c-.7-.5-1.6 0-1.6.8v4.5L4.6 5.4C3.9 4.9 3 5.4 3 6.2z" fill={color} />
    </svg>
  );
}
const stroke = { fill: "none", stroke: "var(--ink)", strokeWidth: 2, strokeLinecap: "round", strokeLinejoin: "round" };
const ListNumber = () => (
  <svg width="17" height="17" viewBox="0 0 24 24" aria-hidden="true">
    <path d="M10 6h11M10 12h11M10 18h11" {...stroke} stroke="var(--ink-2)" />
    <text x="2" y="8.5" fontSize="7" fill="var(--ink-2)" fontWeight="700">1</text><text x="2" y="14.5" fontSize="7" fill="var(--ink-2)" fontWeight="700">2</text>
    <text x="2" y="20.5" fontSize="7" fill="var(--ink-2)" fontWeight="700">3</text>
  </svg>
);
const RepeatGlyph = ({ one }) => (
  <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true">
    <path d="M4 11V9a3 3 0 0 1 3-3h12l-3-3M20 13v2a3 3 0 0 1-3 3H5l3 3" {...stroke} stroke="currentColor" />
    {one && <text x="10" y="15" fontSize="7" fill="currentColor" fontWeight="800">1</text>}
  </svg>
);
const ShuffleGlyph = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true">
    <path d="M3 7h3.5c2 0 3.2 1 4.3 2.7l2.4 4.6c1.1 1.7 2.3 2.7 4.3 2.7H21M18 14l3 3-3 3M3 17h3.5c1.2 0 2-.3 2.8-1M21 7h-3.5c-1.2 0-2 .3-2.8 1M18 4l3 3-3 3" {...stroke} stroke="currentColor" />
  </svg>
);
const SearchGlyph = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5" {...stroke} /><path d="M15.5 15.5L21 21" {...stroke} /></svg>
);
const FilterGlyph = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6h18M6.5 12h11M10 18h4" {...stroke} stroke="currentColor" /></svg>
);
const ArrowsGlyph = () => (
  <svg width="17" height="17" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 20V4M3 8l4-4 4 4M17 4v16M13 16l4 4 4-4" {...stroke} stroke="var(--bar-glyph)" /></svg>
);
