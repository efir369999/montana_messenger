import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Page, Section } from "./Settings.jsx";
import { AppIcon, LibraryPage } from "./Library.jsx";
import iconGlass from "./assets/icon_glass.png";
import iconGold from "./assets/icon_gold.png";
import iconSun from "./assets/icon_sun.png";
import iconJuno from "./assets/icon_juno.png";
import iconPyramid from "./assets/icon_pyramid.png";

/** THE APP'S ICON (iOS AppIconPicker: setAlternateIconName): the same five pictures; on Windows the window's, the taskbar's and
 *  the tray's icon. The choice is this machine's, and it is worn again at every start. */
export const ICONS = [["glass", iconGlass, "Liquid glass"], ["gold", iconGold, "Gold on black"], ["sun", iconSun, "Sunlight"],
                      ["juno", iconJuno, "Juno"], ["pyramid", iconPyramid, "Pyramid"]];
const ICON = "appIcon";
export function readIcon() {
  try { const k = localStorage.getItem(ICON); return ICONS.some((i) => i[0] === k) ? k : "glass"; } catch { return "glass"; }
}
/** The icon worn: the picture drawn at 128 and its pixels handed to the window (the primary icon is the one the program carries). */
export async function applyIcon(name = readIcon(), always = false) {
  if (name === "glass" && !always) return;
  const src = ICONS.find((i) => i[0] === name)?.[1];
  if (!src) return;
  let img;
  // the picture as an image of the page (the page's own pictures are images; it fetches nothing: connect-src is the IPC's alone)
  try { img = new Image(); img.src = src; await img.decode(); }
  catch (e) { invoke("trace", { line: `app_icon unread ${name} ${String(e).slice(0, 80)}` }).catch(() => {}); return; }
  const side = 128, c = document.createElement("canvas");
  c.width = side; c.height = side;
  const g = c.getContext("2d");
  g.drawImage(img, 0, 0, side, side);
  const rgba = g.getImageData(0, 0, side, side).data;
  const body = new Uint8Array(8 + rgba.length);
  new DataView(body.buffer).setUint32(0, side, true);
  new DataView(body.buffer).setUint32(4, side, true);
  body.set(rgba, 8);
  await invoke("app_icon", body, { headers: { name } }).catch((e) => invoke("trace", { line: `app_icon refused ${name} ${String(e).slice(0, 80)}` }).catch(() => {}));
}

/** THE ONE BUBBLE STYLE (iOS MTBubbleStyle, AppearanceView «Message style»): Montana -- the platform's blue and grey, the
 *  default; Classic -- my blue and a deeper grey; Custom -- each side's fill from its top to its bottom at its opacity, its
 *  words' colour and its rim. A setting of this machine (iOS keeps it in the device's own defaults). */
const KEY = "look";
const FLOOR = 0.2;   // iOS BT.fillFloor
export const DEFAULTS = {
  style: "montana",
  mine: { fill1: "#0a85ff", fill2: "#0a85ff", opacity: FLOOR, text: "#ffffff", outline: "#ffffff", outlineOp: 0, outlineW: 0 },
  peer: { fill1: "#6b6b6b", fill2: "#6b6b6b", opacity: FLOOR, text: "#ffffff", outline: "#ffffff", outlineOp: 0, outlineW: 0 },
};

export function readLook() {
  try {
    const k = JSON.parse(localStorage.getItem(KEY) || "null");
    if (!k) return DEFAULTS;
    return { style: k.style || "montana", mine: { ...DEFAULTS.mine, ...k.mine }, peer: { ...DEFAULTS.peer, ...k.peer } };
  } catch { return DEFAULTS; }
}

const rgba = (hex, a) => {
  const n = parseInt(hex.replace("#", ""), 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
};

/** The style laid on the page: the bubbles read their fill, words and rim from it. */
export function applyLook(look = readLook()) {
  const root = document.documentElement.style;
  for (const side of ["mine", "peer"]) {
    const v = look[side];
    if (look.style === "custom") {
      root.setProperty(`--${side}-fill`, `linear-gradient(${rgba(v.fill1, v.opacity)}, ${rgba(v.fill2, v.opacity)})`);
      root.setProperty(`--${side}-text`, v.text);
      root.setProperty(`--${side}-rim`, v.outlineW > 0 && v.outlineOp > 0 ? `inset 0 0 0 ${v.outlineW}px ${rgba(v.outline, v.outlineOp)}` : "none");
    } else if (look.style === "classic") {
      root.setProperty(`--${side}-fill`, side === "mine" ? "var(--blue)" : "#2e2e2e");
      root.setProperty(`--${side}-text`, "#ffffff");
      root.setProperty(`--${side}-rim`, "none");
    } else {
      for (const p of ["fill", "text", "rim"]) root.removeProperty(`--${side}-${p}`);
    }
  }
}

/** THE FEED'S MOTION (iOS MTLetterMotion, AppearanceView «Feed motion»): one spring for the letters that arrive -- its
 *  springiness 0 to 0.4 (0.18 by default) and its duration 0.25 to 0.8 s (0.55 by default); a value out of its range is held
 *  to it. The system's reduced motion stands over it (the stylesheet's own query). */
/** THE NOTE'S PICTURE QUALITY (iOS MontanaNoteQuality, the author's word 18.09): the camera's height and the encoder's rate;
 *  the file's square (480) never changes, so every build reads every note. Medium by default. */
export const NOTE_QUALITY = [["low", "Min"], ["medium", "Medium"], ["high", "Max"]];
const NOTE_KEY = "noteQuality";
export const NOTE_STEPS = { low: { height: 480, rate: 900000 }, medium: { height: 720, rate: 1500000 }, high: { height: 1080, rate: 2500000 } };
export function readNoteQuality() {
  try { const k = localStorage.getItem(NOTE_KEY); return NOTE_STEPS[k] ? k : "medium"; } catch { return "medium"; }
}

const MOTION = "motion";
export const MOTION_DEFAULTS = { bounce: 0.18, duration: 0.55 };
const held = (v, lo, hi, d) => (Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d);
export function readMotion() {
  try {
    const m = JSON.parse(localStorage.getItem(MOTION) || "null") || {};
    return { bounce: held(m.bounce, 0, 0.4, MOTION_DEFAULTS.bounce), duration: held(m.duration, 0.25, 0.8, MOTION_DEFAULTS.duration) };
  } catch { return MOTION_DEFAULTS; }
}
/** A spring of SwiftUI's own measure (.spring(duration:bounce:): damping 1 - bounce, the period its duration) as a CSS easing:
 *  the spring's own path, sampled, and the time it takes to settle. */
export function springOf({ bounce, duration }) {
  const z = 1 - bounce, w = (2 * Math.PI) / duration, total = duration * (1.2 + bounce * 2);
  const at = (t) => {
    if (z >= 1) return 1 - Math.exp(-w * t) * (1 + w * t);
    const wd = w * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + (z * w / wd) * Math.sin(wd * t));
  };
  const points = Array.from({ length: 41 }, (_, i) => (i === 40 ? 1 : at((total * i) / 40)).toFixed(4));
  return { ease: `linear(${points.join(", ")})`, ms: Math.round(total * 1000) };
}
export function applyMotion(m = readMotion()) {
  const s = springOf(m), root = document.documentElement.style;
  root.setProperty("--letter-ease", s.ease);
  root.setProperty("--letter-ms", `${s.ms}ms`);
}

function keepLook(look) {
  try { localStorage.setItem(KEY, JSON.stringify(look)); } catch { /* the look lives while the window does */ }
  applyLook(look);
}

/** APPEARANCE (iOS AppearanceView): the preview is the chat's own bubbles; the message style; a custom style's two sides,
 *  swapped or reset to Montana. */
export function LookPage({ onClose }) {
  const [sub, setSub] = useState(null);
  const [quality, setQuality] = useState(readNoteQuality);
  const [look, setLook] = useState(readLook);
  const [motion, setMotion] = useState(readMotion);
  const [icon, setIcon] = useState(readIcon);
  const wear = (name) => {
    setIcon(name);
    try { localStorage.setItem(ICON, name); } catch { /* the icon lives while the window does */ }
    applyIcon(name, true);
  };
  const move = (next) => {
    setMotion(next);
    try { localStorage.setItem(MOTION, JSON.stringify(next)); } catch { /* the motion lives while the window does */ }
    applyMotion(next);
  };
  const put = (next) => { setLook(next); keepLook(next); };
  const side = (s, k, v) => put({ ...look, [s]: { ...look[s], [k]: v } });
  const colour = (s, k, title) => (
    <label className="set-row look-row"><span className="row-title">{t(title)}</span>
      <input type="color" value={look[s][k]} aria-label={`${t(s === "mine" ? "Your bubble" : "Their bubble")}: ${t(title)}`} onChange={(e) => side(s, k, e.target.value)} /></label>
  );
  const slider = (s, k, title, min, max, step) => (
    <label className="set-row look-row"><span className="row-title">{t(title)}</span>
      <input type="range" min={min} max={max} step={step} value={look[s][k]} aria-label={`${t(s === "mine" ? "Your bubble" : "Their bubble")}: ${t(title)}`}
             onChange={(e) => side(s, k, Number(e.target.value))} /></label>
  );
  const sideSection = (s) => (
    <Section head={t(s === "mine" ? "Your bubble" : "Their bubble")}>
      {colour(s, "fill1", "Fill top")}
      {colour(s, "fill2", "Fill bottom")}
      {slider(s, "opacity", "Fill opacity", FLOOR, 1, 0.01)}
      {colour(s, "text", "Text")}
      {colour(s, "outline", "Outline")}
      {slider(s, "outlineOp", "Outline opacity", 0, 1, 0.01)}
      {slider(s, "outlineW", "Outline width", 0, 3, 0.1)}
    </Section>
  );
  if (sub === "library") return <LibraryPage onClose={() => setSub(null)} />;
  return (
    <Page title={t("Appearance")} onClose={onClose} back>
      <div className="look-preview">
        <div className="bubble-row theirs"><div className="bubble">{t("Their message")}</div></div>
        <div className="bubble-row mine"><div className="bubble">{t("Your message")}</div></div>
      </div>
      <Section head={t("Message style")} foot={t("Montana: yours in the system blue, others' in grey. Classic: yours in your bubble colour, others' in dark grey. Custom: the colours you set below.")}>
        <div className="slow-steps" role="radiogroup" aria-label={t("Message style")}>
          {[["montana", "Montana (default)"], ["classic", "Classic"], ["custom", "Custom"]].map(([k, word]) => (
            <button key={k} role="radio" aria-checked={look.style === k} className={"slow-step" + (look.style === k ? " on" : "")}
                    onClick={() => put({ ...look, style: k })}>{t(word)}</button>
          ))}
        </div>
      </Section>
      <Section head={t("Application icons")}>
        <button className="set-row library-row" onClick={() => setSub("library")}>
          <AppIcon app="chats" side={48} /><span className="row-title">{t("Application icons")}</span><span className="row-value">›</span>
        </button>
      </Section>
      <Section head={t("App icon")}>
        <div className="icon-choices" role="radiogroup" aria-label={t("App icon")}>
          {ICONS.map(([k, src, word]) => (
            <button key={k} role="radio" aria-checked={icon === k} aria-label={t(word)} className={"icon-choice" + (icon === k ? " on" : "")}
                    onClick={() => wear(k)}><img src={src} alt="" /></button>
          ))}
        </div>
      </Section>
      <Section head={t("Video note quality")} foot={t("Max takes the camera's sharpest picture at the highest bitrate, Min makes the lightest file. A camera that cannot keep up steps down by itself.")}>
        <div className="slow-steps" role="radiogroup" aria-label={t("Video note quality")}>
          {NOTE_QUALITY.map(([k, word]) => (
            <button key={k} role="radio" aria-checked={quality === k} className={"slow-step" + (quality === k ? " on" : "")}
                    onClick={() => { setQuality(k); try { localStorage.setItem(NOTE_KEY, k); } catch { /* lives while the window does */ } }}>{t(word)}</button>
          ))}
        </div>
      </Section>
      <Section head={t("Feed motion")} foot={t("Adjusts new messages. Reduce Motion takes priority.")}>
        <label className="set-row look-row"><span className="row-title">{t("Springiness")}</span>
          <input type="range" min={0} max={0.4} step={0.01} value={motion.bounce} aria-label={t("Springiness")}
                 onChange={(e) => move({ ...motion, bounce: Number(e.target.value) })} /></label>
        <label className="set-row look-row"><span className="row-title">{t("Animation duration")}</span>
          <input type="range" min={0.25} max={0.8} step={0.01} value={motion.duration} aria-label={t("Animation duration")}
                 onChange={(e) => move({ ...motion, duration: Number(e.target.value) })} /></label>
        <button className="set-row" onClick={() => move(MOTION_DEFAULTS)}><span className="row-title" style={{ color: "var(--blue)" }}>{t("Reset motion")}</span></button>
      </Section>
      {look.style === "custom" && sideSection("mine")}
      {look.style === "custom" && sideSection("peer")}
      {look.style === "custom" && (
        <Section>
          <button className="set-row" onClick={() => put({ ...look, mine: look.peer, peer: look.mine })}><span className="row-title" style={{ color: "var(--blue)" }}>{t("Swap sides")}</span></button>
          <button className="set-row" onClick={() => put({ ...DEFAULTS, style: "custom" })}><span className="row-title" style={{ color: "var(--blue)" }}>{t("Reset to Montana")}</span></button>
        </Section>
      )}
    </Page>
  );
}
