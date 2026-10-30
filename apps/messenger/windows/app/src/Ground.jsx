import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { Page } from "./Settings.jsx";
import { SelfFace } from "./Chats.jsx";
import { useFile } from "./Media.jsx";
import montana from "./assets/ground_montana.png";
import burgundy from "./assets/montana_burgundy.png";
import logo from "./assets/logo.png";

/** THE GROUND OF ONE CONVERSATION AND OF THE PAGES (iOS MTWallpaper): a ground chosen for a chat stands over my page's ground;
 *  my page's ground stands where none is chosen -- behind the chats, the contacts, the settings and every chat that chose
 *  nothing, softened as the pages wear it. The choice is kept on this machine only, as iOS keeps it in its settings; a photo
 *  ground is kept sealed in the person's media store. */
export const PAGE = "page";
/** The one default (iOS 2304 MTWallpaper.byDefault): the app's own dark ground with the Montana pattern -- the gold's place until
 *  23.10.2026. */
export const BY_DEFAULT = "default";
/** THE GOLD GROUND IS GONE WHOLE (iOS 2304 MTWallpaper.retired, the author's words 23.10.2026 02:09 and 12:50 MSK: «remove the gold
 *  completely»): no choice, no default and no picture any more; a choice stored or a ground told by a correspondent under its name
 *  wears the default ground. */
const RETIRED = new Set(["gold"]);
/** Indigo keeps the name it was born with (iOS: phones store «aurora»). */
export const MONTANA_OFFERED = ["aurora", "burgundy"];
export const SYSTEM_OFFERED = ["montana", "default", "black", "dark", "blue", "sky", "dusk", "water", "rose", "forest"];
export const NAMES = {
  montana: "Montana ground", default: "Default ground", black: "Black ground", dark: "Dark ground", blue: "Blue ground",
  sky: "Sky", dusk: "Dusk", water: "Water", aurora: "Indigo", burgundy: "Burgundy", rose: "Rose", forest: "Forest",
};
/** The softness of my page's ground where the pages wear it (iOS MTSoftGround: radius 36 points, light 0.72). */
const SOFT = 36;

const rgb = (r, g, b, a = 1) => `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${a})`;
const dark = `linear-gradient(180deg, ${rgb(0.05, 0.05, 0.07)}, ${rgb(0.09, 0.08, 0.06)}, ${rgb(0.13, 0.10, 0.05)})`;   // montanaDarkGradient
const picture = (src) => `center / cover no-repeat url("${src}")`;

/** THE LOGO'S PATTERN (iOS MontanaLogoPattern): cells of 140 points, the Logo at 0.3 of the cell in its middle, every other row a
 *  half cell to the right, the whole at 0.035 -- drawn once into a tile of two rows that repeats; until the Logo is read, the
 *  dark gradient alone. */
let pattern = null;
{
  const img = new Image();
  img.onload = () => {
    const tile = 140, side = tile * 0.3, c = document.createElement("canvas");
    c.width = tile; c.height = tile * 2;
    const g = c.getContext("2d");
    g.globalAlpha = 0.035;
    for (const [x, y] of [[tile / 2, tile / 2], [tile, tile * 1.5], [0, tile * 1.5]]) g.drawImage(img, x - side / 2, y - side / 2, side, side);
    pattern = `0 0 / ${tile}px ${tile * 2}px repeat url("${c.toDataURL()}")`;
    window.dispatchEvent(new CustomEvent("montana-ground"));
  };
  img.src = logo;
}

/** ONE PAINT PER GROUND (iOS MTWallpaper.paint): the full ground and its tile draw the very same paint. */
export function paint(n) {
  switch (n) {
    case "montana": return picture(montana);
    case "burgundy": return picture(burgundy);
    case "black": return "#000";
    case "dark": return dark;
    case "blue": return `linear-gradient(180deg, ${rgb(0.10, 0.20, 0.32)}, ${rgb(0.05, 0.10, 0.18)})`;
    case "sky": return `radial-gradient(circle at 70% 22%, ${rgb(1, 1, 1, 0.55)}, transparent 320px), linear-gradient(180deg, ${rgb(0.36, 0.62, 0.86)}, ${rgb(0.74, 0.86, 0.94)})`;
    case "dusk": return `radial-gradient(circle at 50% 86%, ${rgb(1, 0.85, 0.60, 0.7)}, transparent 260px), linear-gradient(180deg, ${rgb(0.13, 0.12, 0.28)}, ${rgb(0.58, 0.32, 0.36)}, ${rgb(0.95, 0.62, 0.36)})`;
    case "water": return `conic-gradient(from 0deg at 40% 40%, ${rgb(1, 1, 1, 0.18)}, transparent, ${rgb(0.70, 0.85, 0.90, 0.25)}, transparent), linear-gradient(135deg, ${rgb(0.62, 0.80, 0.84)}, ${rgb(0.90, 0.93, 0.94)}, ${rgb(0.55, 0.72, 0.80)})`;
    case "aurora": return `radial-gradient(circle at 32% 38%, ${rgb(0.25, 0.85, 0.75, 0.65)}, transparent 280px), radial-gradient(circle at 72% 60%, ${rgb(0.55, 0.35, 0.95, 0.6)}, transparent 300px), linear-gradient(180deg, ${rgb(0.04, 0.04, 0.12)}, ${rgb(0.08, 0.10, 0.24)})`;
    case "rose": return `radial-gradient(circle at 30% 75%, ${rgb(1, 0.75, 0.85, 0.5)}, transparent 280px), linear-gradient(180deg, ${rgb(0.42, 0.10, 0.36)}, ${rgb(0.95, 0.35, 0.62)})`;
    case "forest": return `radial-gradient(circle at 65% 30%, ${rgb(0.55, 0.85, 0.60, 0.28)}, transparent 260px), linear-gradient(135deg, ${rgb(0.05, 0.18, 0.16)}, ${rgb(0.12, 0.36, 0.30)}, ${rgb(0.06, 0.14, 0.14)})`;
    default: return pattern ? `${pattern}, ${dark}` : dark;   // «default» and every name unknown here: the pattern over the dark gradient
  }
}

const KEY = (conv) => "chatWall." + conv;
/** What a conversation (or the page) chose: «general» (nothing: my page's ground; for the page itself -- no ground), a named
 *  ground, or a photo of the person's kept in the media store. */
export function choice(conv) {
  let s = null;
  try { s = localStorage.getItem(KEY(conv)); } catch { /* the choice is only kept where storage is */ }
  if (s === null && conv === PAGE) return { named: BY_DEFAULT };
  if (s?.startsWith("named:")) return { named: RETIRED.has(s.slice(6)) ? BY_DEFAULT : s.slice(6) };
  if (s?.startsWith("photo:")) return { photo: s.slice(6) };
  return { general: true };
}
export function choose(conv, c) {
  const old = choice(conv).photo;
  try {
    // my page's «No background» is kept, told apart from nothing chosen (iOS set)
    const v = c.named ? "named:" + c.named : c.photo ? "photo:" + c.photo : conv === PAGE ? "general" : null;
    if (v === null) localStorage.removeItem(KEY(conv)); else localStorage.setItem(KEY(conv), v);
  } catch { /* nothing kept: the ground stands for this window only */ }
  if (old && old !== c.photo) invoke("ground_forget", { name: old }).catch(() => {});
  if (conv === PAGE) tellPage();
  window.dispatchEvent(new CustomEvent("montana-ground"));
}
/** My page's ground as my correspondents get it (iOS MTPageGround): Rust carries it to everyone whose build reads it. */
function tellPage() {
  const c = choice(PAGE);
  invoke("ground_page_set", { g: c.named ? "n:" + c.named : c.photo ? "p:" + c.photo : "" }).catch(() => {});
}
let told = false;

/** A CORRESPONDENT'S PAGE GROUND (iOS MTPageGround on their page): drawn as it came, sharp. */
export function TheirGround({ chat }) {
  const [g, setG] = useState(null);
  useEffect(() => { invoke("peer_ground", { chat }).then(setG).catch(() => {}); }, [chat]);
  if (!g || (!g.named && !g.photo)) return <PageGround />;
  return <Layer c={g.photo ? { photo: g.photo } : { named: g.named }} />;
}
const same = (a, b) => (!!a.general && !!b.general) || (!!a.named && a.named === b.named) || (!!a.photo && a.photo === b.photo);

function useGround() {
  const [, set] = useState(0);
  useEffect(() => {
    const f = () => set((n) => n + 1);
    window.addEventListener("montana-ground", f);
    return () => window.removeEventListener("montana-ground", f);
  }, []);
}

/** THE INK FOLLOWS THE GROUND UNDER IT (iOS 2304 MTWallpaper.scheme, lightGrounds, bright; the author's word 22.10 18:21: «white on the
 *  dark, black on the light»): the light gradients -- sky, water -- and a photo whose mean brightness (Rec.709 over its miniature
 *  of 8 x 8) passes the middle wear the dark ink; every other ground the white one. The place a ground stands under says it by its
 *  «data-ink» (the root by my page's ground, a chat or a page by its own); a bubble keeps its own dark plate on any ground. */
const LIGHT = new Set(["sky", "water"]);
const brightness = new Map();   // a photo's address -> whether it is light, measured once a run
function bright(url) {
  if (brightness.has(url)) return Promise.resolve(brightness.get(url));
  return new Promise((done) => {
    const img = new Image();
    img.onload = () => {
      const c = document.createElement("canvas");
      c.width = 8; c.height = 8;
      const g = c.getContext("2d");
      g.drawImage(img, 0, 0, 8, 8);
      const d = g.getImageData(0, 0, 8, 8).data;
      let sum = 0;
      for (let i = 0; i < d.length; i += 4) sum += (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255;
      const light = sum / 64 > 0.5;
      brightness.set(url, light);
      done(light);
    };
    img.onerror = () => done(false);
    img.src = url;
  });
}
function useInk(box, c, url, root) {
  useEffect(() => {
    let gone = false;
    const target = root ? document.documentElement : box.current?.parentElement;
    if (!target) return;
    const wear = (light) => { if (!gone) target.dataset.ink = light ? "light" : "dark"; };
    if (c.photo) { if (url) bright(url).then(wear); }
    else wear(!!c.named && LIGHT.has(c.named));
    return () => { gone = true; if (!root) delete target.dataset.ink; };
  }, [c.named, c.photo, url, root]);
}

/** One ground drawn: a named one by its paint, a photo by its file; `blur` softens it as the pages wear it; `root` -- its ink is the
 *  whole window's (my page's ground), else the place it stands in wears it. */
function Layer({ c, blur = 0, root = false }) {
  const url = useFile(c.photo || "", !!c.photo, "jpg");
  const bg = url ? picture(url) : c.named ? paint(c.named) : "#000";
  const box = useRef(null);
  useInk(box, c, url, root);
  return (
    <div className="ground-box" aria-hidden="true" ref={box}>
      <div className={"ground" + (blur ? " soft" : "")} style={{ background: bg, ...(blur ? { "--soft": `${blur}px` } : {}) }} />
    </div>
  );
}

/** MY PAGE'S GROUND, SOFT (iOS MTUnderBarGround + MTSoftGround): behind the chats, the pages and every chat that chose none. */
export function PageGround() {
  useGround();
  if (!told) { told = true; tellPage(); }   // once a run: what this machine chose is what Rust says
  return <Layer c={choice(PAGE)} blur={SOFT} root />;
}

/** A CHAT'S OWN GROUND, SHARP (iOS MontanaChatBackdrop): nothing where the chat chose none -- my page's soft ground stands. */
export function ChatGround({ chat }) {
  useGround();
  const own = choice(chat);
  return own.general ? null : <Layer c={own} />;
}

/** A GROUND'S MINIATURE IS THE GROUND AS IT WILL STAND (iOS MTGroundMiniature): the window's own frame scaled down -- the same
 *  drawing, the same crop -- softened where it will be worn soft. */
function Mini({ conv, c }) {
  const box = useRef(null);
  const [k, setK] = useState(0);
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setK(el.clientWidth / Math.max(1, window.innerWidth)));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const soft = conv === PAGE || c.general;
  const worn = conv !== PAGE && c.general ? choice(PAGE) : c;
  const w = Math.max(1, window.innerWidth), h = Math.max(1, window.innerHeight);
  return (
    <div className="ground-mini" ref={box} style={{ aspectRatio: w / h }}>
      {k > 0 && <div className="ground-mini-win" style={{ width: w, height: h, transform: `scale(${k})` }}><Layer c={worn} blur={soft ? SOFT : 0} /></div>}
    </div>
  );
}

/** THE CHOOSER (iOS MTWallpaperPicker): two tabs clearly apart -- the ready grounds, Montana's leading, and the photos; a tap
 *  shows the ground in its preview, whose checkmark keeps it. `onDone` is what the chooser's own checkmark goes on to (the
 *  first screen makes the person after their ground is chosen); else it closes. */
export function GroundPicker({ conv, onClose, onDone }) {
  useGround();
  const page = conv === PAGE;
  const [tab, setTab] = useState(0);
  const [preview, setPreview] = useState(null);
  const file = useRef(null);
  const now = choice(conv);
  const montanaTiles = MONTANA_OFFERED.map((n) => ({ named: n }));
  const systemTiles = [...(page ? [] : [{ general: true }]), ...SYSTEM_OFFERED.map((n) => ({ named: n }))];
  const extra = [...montanaTiles, ...systemTiles].some((c) => same(c, now)) ? null : now;
  const label = (c) => t(c.general ? (page ? "No background" : "Same as my page") : c.named ? NAMES[c.named] || "Default ground" : "Choose photo");
  const tile = (c, named) => {
    const on = same(c, now);
    return (
      <div key={JSON.stringify(c)} className="ground-cell">
        <button className={"ground-tile" + (on ? " on" : "")} role="radio" aria-checked={on} aria-label={label(c)}
                onClick={() => (c.photo ? setTab(1) : setPreview({ c }))}>
          <Mini conv={conv} c={c} />
          {on && <span className="ground-check"><Glyph name="tick" size={14} color="#fff" /></span>}
        </button>
        {named && <span className="ground-name">{label(c)}</span>}
      </div>
    );
  };
  if (preview) return <GroundPreview conv={conv} candidate={preview} onClose={() => setPreview(null)} />;
  return (
    <Page title={t(page ? "Page background" : "Chat background")} onClose={onClose}
          right={<button className="glass-mark" onClick={() => { invoke("trace", { line: `ground chooser done page=${page ? 1 : 0}` }).catch(() => {}); (onDone || onClose)(); }}
                         aria-label={t("Done")}><Glyph name="tick" size={18} color="#fff" /></button>}>
      <div className="slow-steps ground-tabs" role="radiogroup">
        {["Wallpapers", "Photos"].map((w, i) => (
          <button key={w} role="radio" aria-checked={tab === i} className={"slow-step" + (tab === i ? " on" : "")} onClick={() => setTab(i)}>{t(w)}</button>
        ))}
      </div>
      {tab === 0 && (
        <div className="ground-ready">
          <div className="ground-head">{t("Montana backgrounds")}</div>
          <div className="ground-grid">{montanaTiles.map((c) => tile(c, true))}</div>
          <div className="ground-head">{t("System backgrounds")}</div>
          <div className="ground-grid">{systemTiles.map((c) => tile(c, false))}</div>
          {extra && <div className="ground-grid">{tile(extra, false)}</div>}
        </div>
      )}
      {tab === 1 && (
        <div className="ground-photos">
          <input ref={file} type="file" accept="image/*" hidden
                 onChange={(e) => { const f = e.target.files[0]; e.target.value = ""; if (f) setPreview({ file: f }); }} />
          {now.photo && <div className="ground-grid">{tile(now, false)}</div>}
          <button className="set-row accent ground-choose" onClick={() => file.current.click()}>
            <Glyph name="photo" size={18} color="#fff" /><span className="row-title">{t("Choose photo")}</span>
          </button>
        </div>
      )}
    </Page>
  );
}

/** THE PREVIEW (iOS MTWallpaperPreview): the ground on the whole page, the chat's bubbles over it (or my face and name, for my
 *  page); a photo is placed by the mouse -- dragged, sized by the wheel -- and kept as it stands, at the window's pixels. */
function GroundPreview({ conv, candidate, onClose }) {
  const page = conv === PAGE;
  const [src, setSrc] = useState(null);
  const [img, setImg] = useState(null);
  const [at, setAt] = useState({ x: 0, y: 0, z: 1 });
  const [busy, setBusy] = useState(false);
  const frame = useRef(null);
  const drag = useRef(null);
  const [me, setMe] = useState(null);
  useEffect(() => { if (page) invoke("identity_state").then(setMe).catch(() => {}); }, [page]);
  useEffect(() => {
    if (!candidate.file) return;
    const u = URL.createObjectURL(candidate.file);
    const i = new Image();
    i.onload = () => { setImg(i); setSrc(u); };
    i.src = u;
    return () => URL.revokeObjectURL(u);
  }, [candidate.file]);
  // the photo covers the frame at its smallest; the mouse moves it, the wheel sizes it, never leaving an edge bare
  const box = () => frame.current?.getBoundingClientRect() || { width: window.innerWidth, height: window.innerHeight };
  const placed = (p) => {
    if (!img) return p;
    const b = box();
    const k = Math.max(b.width / img.naturalWidth, b.height / img.naturalHeight) * p.z;
    const w = img.naturalWidth * k, h = img.naturalHeight * k;
    return { ...p, x: Math.min(0, Math.max(b.width - w, p.x)), y: Math.min(0, Math.max(b.height - h, p.y)), w, h };
  };
  useEffect(() => {
    if (!img) return;
    const b = box();
    const k = Math.max(b.width / img.naturalWidth, b.height / img.naturalHeight);
    setAt({ x: (b.width - img.naturalWidth * k) / 2, y: (b.height - img.naturalHeight * k) / 2, z: 1 });
  }, [img]);
  const p = placed(at);
  const keep = async () => {
    if (busy) return;
    setBusy(true);
    try {
      if (candidate.c) {
        choose(conv, candidate.c);
        invoke("trace", { line: `ground kept ${page ? "page" : "chat"} ${candidate.c.named || "general"}` }).catch(() => {});
      } else if (img) {
        // what stood in the frame, at the window's pixels and no larger (iOS saveRendered / lightData)
        const b = box();
        const k = Math.min(window.devicePixelRatio || 1, 2560 / Math.max(b.width, b.height));
        const cv = document.createElement("canvas");
        cv.width = Math.round(b.width * k); cv.height = Math.round(b.height * k);
        cv.getContext("2d").drawImage(img, p.x * k, p.y * k, p.w * k, p.h * k);
        const blob = await new Promise((ok) => cv.toBlob(ok, "image/jpeg", 0.9));
        const name = await invoke("ground_keep", new Uint8Array(await blob.arrayBuffer()));
        choose(conv, { photo: name });
        invoke("trace", { line: `ground kept ${page ? "page" : "chat"} photo ${cv.width}x${cv.height}` }).catch(() => {});
      }
      onClose();
    } catch { setBusy(false); }
  };
  return (
    <div className="page-over ground-preview" role="dialog" aria-label={t("Preview")}>
      <div className="ground-frame" ref={frame}
           onPointerDown={(e) => { if (!img) return; drag.current = { x: e.clientX, y: e.clientY, p: { ...p } }; e.currentTarget.setPointerCapture(e.pointerId); }}
           onPointerMove={(e) => { const d = drag.current; if (d) setAt({ ...d.p, x: d.p.x + e.clientX - d.x, y: d.p.y + e.clientY - d.y }); }}
           onPointerUp={() => { drag.current = null; }}
           onWheel={(e) => { if (img) setAt((a) => ({ ...a, z: Math.min(5, Math.max(1, a.z * (e.deltaY < 0 ? 1.1 : 0.9))) })); }}>
        {img ? <img className="ground-placed" src={src} alt="" draggable={false} style={{ left: p.x, top: p.y, width: p.w, height: p.h }} />
             : candidate.c && <Layer c={candidate.c.general && !page ? choice(PAGE) : candidate.c} blur={candidate.c.general && !page ? SOFT : 0} />}
      </div>
      <header className="page-bar">
        <button className="glass-mark" onClick={onClose} aria-label={t("Close")}><Glyph name="close" size={18} color="var(--bar-glyph)" /></button>
        <div className="page-title">{t("Preview")}</div>
        <div className="page-right">
          <button className="glass-mark" onClick={keep} disabled={busy || (candidate.file && !img)} aria-label={t("Done")}><Glyph name="tick" size={18} color="#fff" /></button>
        </div>
      </header>
      {page ? (
        <div className="me-head ground-dress">
          {me && <SelfFace name={me.name} version={me.face} size={104} />}
          {me && <div className="me-bubble name">{me.name}</div>}
        </div>
      ) : (
        <div className="ground-dress ground-bubbles">
          <div className="bubble-row theirs"><div className="bubble">{t("Hello! This is the Montana style.")}</div></div>
          <div className="bubble-row mine"><div className="bubble">{t("Your message")}</div></div>
          <div className="bubble-row theirs"><div className="bubble">{t("Their message")}</div></div>
        </div>
      )}
    </div>
  );
}
