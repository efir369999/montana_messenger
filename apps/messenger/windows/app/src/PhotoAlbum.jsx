import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Glyph } from "./TopBar.jsx";
import { useLeave } from "./leave.js";
import { t } from "./strings.js";

const COVER = 96;           // iOS coverSide
const STRIP = 120;          // iOS stripHeight
const BAND = STRIP + 10 + 16;   // the strip's band: the strip, its gap, the foot's inset
const STEP = COVER * 0.72;  // the covers overlap as they recede (iOS HStack spacing -side * 0.28)
const MAX_ZOOM = 4;         // iOS: the system zoom 1…4
const PULL_CLOSE = 120;     // iOS letGo: a pull past 120 points, or a fling past 320, closes
const FLING_CLOSE = 320;

/** THE ONE ALBUM (iOS MontanaPhotoViewer + PhotoPresenter.present(_:among:); the author's words 05.10.2026: «one function
 *  everywhere»): a picture tapped opens among the pictures it stands with, oldest first. The page fits above the strip of covers;
 *  a drag sideways turns the page, a click in the outer 15 % turns it too, a click elsewhere hides and shows the strip and the
 *  marks; the wheel or a double click zooms 1…4 at the cursor and a drag then pans; a pull down past 120 or a fling closes it,
 *  the ground fading to a quarter. A lone picture is the same view without the strip. Esc, the mouse's back button and the close
 *  mark are the Windows hand's way to the same door.
 *  `pages`: [{ key, load: () => Promise<url>, cover?: url }]. */
export default function PhotoAlbum({ pages, start = 0, onClose }) {
  const [at, setAt] = useState(Math.min(Math.max(0, start), pages.length - 1));
  const [urls, setUrls] = useState({});
  const [chrome, setChrome] = useState(true);
  const [zoom, setZoom] = useState({ s: 1, x: 0, y: 0 });
  const [drag, setDrag] = useState({ x: 0, y: 0 });
  const [held, setHeld] = useState(false);   // the hand moves the page: it follows at once, and settles with a spring when let go
  const stage = useRef(null);
  const hand = useRef(null);          // the pointer pressed: where, when, which axis it took
  const click = useRef(null);         // a click waiting to learn whether a second one makes it a double
  const paged = pages.length > 1;
  useLeave(onClose);

  // the page and its two neighbours are read as the page stands (iOS: the controller asks for a neighbour only when reached for)
  useEffect(() => {
    let live = true;
    for (const i of [at, at - 1, at + 1]) {
      const p = pages[i];
      if (!p || urls[p.key]) continue;
      p.load().then((u) => { if (live && u) setUrls((m) => (m[p.key] ? m : { ...m, [p.key]: u })); }).catch(() => {});
    }
    invoke("trace", { line: `photo_page at=${at} among=${pages.length}` }).catch(() => {});
    return () => { live = false; };
  }, [at]);

  const turn = (d) => {
    setAt((x) => Math.min(pages.length - 1, Math.max(0, x + d)));
    setZoom({ s: 1, x: 0, y: 0 });
  };
  useEffect(() => {
    const key = (e) => {
      if (e.key === "ArrowRight") { e.preventDefault(); turn(1); }
      if (e.key === "ArrowLeft") { e.preventDefault(); turn(-1); }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, []);

  // the zoom keeps the point under the cursor where it stands, and the page never leaves the window's middle
  const zoomAt = (s, cx, cy) => {
    const el = stage.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    setZoom((z) => {
      const ns = Math.min(MAX_ZOOM, Math.max(1, s(z.s)));
      if (ns === 1) return { s: 1, x: 0, y: 0 };
      const px = cx - (r.left + r.width / 2), py = cy - (r.top + r.height / 2);
      const k = ns / z.s;
      const bx = ((ns - 1) * r.width) / 2, by = ((ns - 1) * r.height) / 2;
      return { s: ns, x: Math.max(-bx, Math.min(bx, px - (px - z.x) * k)), y: Math.max(-by, Math.min(by, py - (py - z.y) * k)) };
    });
  };
  useEffect(() => {
    const el = stage.current;
    if (!el) return undefined;
    const wheel = (e) => {
      e.preventDefault();
      zoomAt((s) => s * Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0015)), e.clientX, e.clientY);   // a touchpad's pinch comes as ctrl+wheel
    };
    el.addEventListener("wheel", wheel, { passive: false });
    return () => el.removeEventListener("wheel", wheel);
  }, []);

  const down = (e) => {
    if (e.button !== 0) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    hand.current = { x: e.clientX, y: e.clientY, t: performance.now(), axis: null, z: zoom };
  };
  const move = (e) => {
    const h = hand.current;
    if (!h) return;
    const dx = e.clientX - h.x, dy = e.clientY - h.y;
    if (!h.axis) {
      if (Math.hypot(dx, dy) < 6) return;
      h.axis = h.z.s > 1 ? "pan" : paged && Math.abs(dx) > Math.abs(dy) ? "page" : "pull";
      setHeld(true);
    }
    if (h.axis === "pan") {
      const r = stage.current.getBoundingClientRect();
      const bx = ((h.z.s - 1) * r.width) / 2, by = ((h.z.s - 1) * r.height) / 2;
      setZoom({ s: h.z.s, x: Math.max(-bx, Math.min(bx, h.z.x + dx)), y: Math.max(-by, Math.min(by, h.z.y + dy)) });
    } else if (h.axis === "page") {
      setDrag({ x: dx, y: 0 });
    } else {
      setDrag({ x: paged ? 0 : dx, y: dy });
    }
  };
  const up = (e) => {
    const h = hand.current;
    hand.current = null;
    setHeld(false);
    if (!h) return;
    const dx = e.clientX - h.x, dy = e.clientY - h.y;
    const ms = Math.max(1, performance.now() - h.t);
    if (!h.axis) {   // a click: the second within a quarter second is the double that zooms
      if (click.current) {
        clearTimeout(click.current);
        click.current = null;
        zoomAt((s) => (s > 1 ? 1 : 2.5), e.clientX, e.clientY);
        return;
      }
      const r = stage.current.getBoundingClientRect();
      const fx = (e.clientX - r.left) / r.width, zoomed = zoom.s > 1;
      click.current = setTimeout(() => {
        click.current = null;
        if (paged && !zoomed && fx < 0.15) turn(-1);
        else if (paged && !zoomed && fx > 0.85) turn(1);
        else setChrome((c) => !c);
      }, 250);
      return;
    }
    if (h.axis === "page") {
      const w = stage.current.getBoundingClientRect().width;
      if (Math.abs(dx) > w * 0.2 || Math.abs(dx) / ms > 0.5) turn(dx < 0 ? 1 : -1);
    } else if (h.axis === "pull") {
      const gone = paged ? Math.abs(dy) : Math.hypot(dx, dy);
      const flung = gone + (gone / ms) * 200;   // where the hand's speed would carry it (iOS predictedEndTranslation)
      if (gone > PULL_CLOSE || flung > FLING_CLOSE + PULL_CLOSE) { onClose(); return; }
    }
    setDrag({ x: 0, y: 0 });
  };

  const page = pages[at];
  const url = page && urls[page.key];
  const dy = paged ? drag.y : Math.hypot(drag.x, drag.y);
  const ground = zoom.s > 1 ? 1 : 1 - Math.min(Math.abs(dy) / 400, 0.75);
  const marks = chrome && zoom.s === 1 && Math.abs(dy) <= 8;
  return (
    <div className="album" role="dialog" aria-label={`${t("Photo")} ${at + 1} / ${pages.length}`} style={{ background: `rgba(0, 0, 0, ${ground})` }}
         onClick={(e) => e.stopPropagation()}>
      <div className={"album-stage" + (held ? "" : " settle")} ref={stage} style={{ bottom: paged && chrome ? BAND : 0 }}
           onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up}>
        <div className="album-page" style={{ transform: `translate(${drag.x}px, ${drag.y}px)` }}>
          {url ? <img src={url} alt="" draggable={false} style={{ transform: `translate(${zoom.x}px, ${zoom.y}px) scale(${zoom.s})` }} />
            : page?.cover ? <img src={page.cover} alt="" draggable={false} className="blur" /> : <span className="spinner" />}
        </div>
      </div>
      {paged && (
        <div className={"album-strip" + (marks ? "" : " away")} aria-hidden={!marks}>
          <div className="album-covers" style={{ transform: `translateX(${-at * STEP - COVER / 2}px)` }}>
            {pages.map((p, i) => {
              const d = Math.max(-1, Math.min(1, i - at));
              const src = p.cover || urls[p.key];
              return (
                <button key={p.key} className={"album-cover" + (i === at ? " on" : "")} aria-label={`${t("Photo")} ${i + 1}`}
                        style={{ left: i * STEP, zIndex: i === at ? 2 : 1, opacity: 1 - 0.35 * Math.abs(d),
                                 transform: `perspective(${COVER / 0.55}px) rotateY(${-d * 55}deg) scale(${1 - 0.28 * Math.abs(d)})` }}
                        onClick={() => { setAt(i); setZoom({ s: 1, x: 0, y: 0 }); }}>
                  {src ? <img src={src} alt="" draggable={false} /> : null}
                </button>
              );
            })}
          </div>
        </div>
      )}
      <button className={"glass-mark album-close" + (marks ? "" : " away")} onClick={onClose} aria-label={t("Close")}>
        <Glyph name="close" size={18} color="#fff" />
      </button>
    </div>
  );
}
