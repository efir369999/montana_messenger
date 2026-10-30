import { useEffect, useRef } from "react";

// THE STROKES OF THE PAGES UNDER THE BAR (iOS MontanaDrawerController, MTTabPan, UIState.turnStroke / folderStroke,
// ContentView.swift 256-368, 2084-2299): a finger -- here the touch, the pen or the mouse's left button -- drawn sideways over the
// page's centre turns the pages of the row, the neighbour sliding in beside it; on the chats page it turns the folders first; on
// the row's first page a stroke to the right drags the drawer out; the window's left edge drags the drawer out from any page; a
// stroke over the dimmed page drags it back. The edge zones of the page -- a sixth of its width, 22 to 80 -- are the rows' own
// swipes. The touchpad's two-finger sideways stroke (the wheel's sideways deltas) turns the pages as the finger does.

/** THE PLATFORM'S SPRING (SwiftUI .spring(response:dampingFraction:), UISpringTimingParameters(dampingRatio:)): a unit mass on a
 *  spring of stiffness (2π/response)², damped at 4π·ζ/response, stepped with the screen's frames, the finger's speed carried in. */
export function spring(from, to, { response = 0.35, damping = 0.9, velocity = 0 } = {}, onFrame, onDone) {
  const k = (2 * Math.PI / response) ** 2, c = (4 * Math.PI * damping) / response;
  let x = from, v = velocity, last = null, id = 0, gone = false;
  const step = (now) => {
    if (gone) return;
    const dt = last == null ? 1 / 60 : Math.min(0.05, (now - last) / 1000);
    last = now;
    const n = Math.max(1, Math.ceil(dt / 0.004)), h = dt / n;
    for (let i = 0; i < n; i++) { v += (-k * (x - to) - c * v) * h; x += v * h; }
    if (Math.abs(x - to) < 0.5 && Math.abs(v) < 8) { onFrame(to); onDone?.(); return; }
    onFrame(x);
    id = requestAnimationFrame(step);
  };
  id = requestAnimationFrame(step);
  return () => { gone = true; cancelAnimationFrame(id); };
}

/** The edge zone the rows keep (MTTabPan.edge): a sixth of the width, 22 to 80. */
export const turnEdge = (w) => Math.max(22, Math.min(w / 6, 80));
/** THE DRAWER'S WIDTH (iOS MontanaSideDrawer.width: round(container * 0.78)), AT MOST 480 ON A WIDE WINDOW: the owner's word
 *  25.10.2026 14:3x, a Windows adaptation and not an iOS number -- a narrow window keeps the original's 78 %, a wide one stops at
 *  480 CSS px (pages.css --drawer, the same rule), a mark to check on several window sizes. */
export const DRAWER_MAX = 480;
export const drawerWidth = (w = window.innerWidth) => Math.min(Math.round(w * 0.78), DRAWER_MAX);
/** The window's left edge where the drawer's own stroke begins (the screen-edge pan's region). */
const EDGE = 16;
/** The reference's rubber band at the row's end (UIState.rubber): range 600, k 0.4. */
const rubber = (o) => (o < 0 ? -1 : 1) * (1 - 1 / ((Math.abs(o) * 0.4) / 600 + 1)) * 600;

/** What stands under the touch and owns its horizontal (MTTabPan.refuses): a strip that scrolls sideways, a slider, a field whose
 *  words the pointer selects; the tabs' stroke gives way over it. */
export function refuses(el, stop) {
  for (let x = el; x && x !== stop && x.nodeType === 1; x = x.parentElement) {
    if (x.matches("input, textarea, select, [contenteditable=true], [data-horizontal]")) return true;
    // a sideways strip: it overflows across and not down (a list that scrolls down keeps the stroke for the pages)
    if (x.scrollWidth > x.clientWidth + 1 && x.scrollHeight <= x.clientHeight + 1 && /(auto|scroll)/.test(getComputedStyle(x).overflowX)) return true;
  }
  return false;
}

/** The speed of the last tenth of a second before `now`, in px/s (the pan's velocity). */
export function speed(samples, now = performance.now()) {
  const recent = samples.filter((s) => now - s.t <= 100);
  if (recent.length < 2) return 0;
  const a = recent[0], b = recent[recent.length - 1];
  return b.t > a.t ? ((b.x - a.x) / (b.t - a.t)) * 1000 : 0;
}

/**
 * The strokes, bound to the shell. `get()` answers the live state:
 *   shell, split, list            -- the elements
 *   drawerOpen                     -- the drawer stands open (React's word)
 *   edgeAllowed()                  -- nothing over the tabs: the window's edge may drag the drawer
 *   turnAllowed()                  -- nothing over the tabs and nothing held by the page (UIState.tabsMayTurn)
 *   atRowStart()                   -- the pane is the row's first (a stroke to the right there is the drawer's)
 *   neighbour(side)                -- the pane beside, +1 the next, -1 the one before; null at the row's end
 *   folderBeside(step)             -- on the chats page, a folder beside the chosen one
 *   ghost(n)                       -- the neighbour to draw beside the pane ({pane, side}) or null
 *   turned(pane)                   -- the pane becomes it (synchronously drawn)
 *   folderTurned(step)             -- the folder beside becomes the chosen one
 *   drawerSet(open), drawerMoving(on) -- the drawer's state and whether it is on its way
 * Returns animateDrawer(open): the drawer's own spring for a tap, a key or a row of the drawer.
 */
export function useStrokes(get) {
  const g = useRef(get);
  g.current = get;
  const api = useRef(null);
  if (!api.current) api.current = makeStrokes(() => g.current());
  useEffect(() => api.current.attach(), []);
  return api.current;
}

function makeStrokes(cfg) {
  let st = null;                 // the stroke under way
  let drawerAnim = null;         // {target, cancel}
  let drawerX = null;            // where the page stands while the drawer moves (null: React's class holds it)
  let turnAnim = null;           // the pages' settle under way: {cancel}
  let turnX = 0, turnN = null;   // the pane's offset and its neighbour ({pane, side})
  let swallowUntil = 0;          // the click that ends a stroke is not a tap
  let wheel = null;              // the touchpad's sideways stroke: {x, samples, idle}

  const width = () => drawerWidth();   // MontanaSideDrawer.width: round(container * 0.78), at most 480 (drawerWidth)

  // THE DRAWER UNDER THE FINGER (MontanaDrawerController.apply): the page slides by t, corners 34 once it moves, the dim at
  // 0.45 × the way gone
  const applyDrawer = (t) => {
    const { split } = cfg();
    if (!split) return;
    const w = width(), x = Math.max(0, Math.min(w, t));
    drawerX = x;
    split.style.transform = `translateX(${x}px)`;
    split.style.borderRadius = x > 0 ? "34px" : "0px";
    split.style.overflow = x > 0 ? "hidden" : "";
    split.style.setProperty("--dim", String(x / w));
  };
  const releaseDrawer = () => {
    const { split } = cfg();
    drawerX = null;
    if (!split) return;
    for (const p of ["transform", "border-radius", "overflow", "--dim"]) split.style.removeProperty(p);
  };
  const drawerFrom = () => (drawerX != null ? drawerX : cfg().drawerOpen ? width() : 0);
  // the settle (MontanaDrawerController.settle): the platform's spring of damping 0.9 in 0.35 s, the finger's speed carried in
  const settleDrawer = (open, velocity) => {
    const target = open ? width() : 0;
    if (drawerAnim?.target === target) return;
    drawerAnim?.cancel();
    const c = cfg();
    c.drawerMoving(true);
    applyDrawer(drawerFrom());
    const cancel = spring(drawerFrom(), target, { response: 0.35, damping: 0.9, velocity }, applyDrawer, () => {
      drawerAnim = null;
      releaseDrawer();
      cfg().drawerMoving(false);
    });
    drawerAnim = { target, cancel };
    if (c.drawerOpen !== open) c.drawerSet(open);
  };

  // THE PAGES UNDER THE FINGER (UIState.turnStroke): the pane at the offset, the neighbour a width away on its side
  const applyTurn = (x, n, w) => {
    const { split } = cfg();
    if (!split) return;
    turnX = x;
    split.classList.add("turning");
    split.style.setProperty("--turn", `${x}px`);
    split.style.setProperty("--turn-p", String(n && w > 0 ? Math.min(1, Math.abs(x) / w) : 0));
    if ((n?.pane ?? null) !== (turnN?.pane ?? null) || (n?.side ?? 0) !== (turnN?.side ?? 0)) {
      turnN = n;
      cfg().ghost(n);
    }
  };
  const releaseTurn = () => {
    const { split } = cfg();
    turnX = 0;
    turnN = null;
    if (split) {
      split.classList.remove("turning");
      split.style.removeProperty("--turn");
      split.style.removeProperty("--turn-p");
    }
    cfg().ghost(null);
  };
  const turnMove = (base, dx, w) => {
    const c = cfg();
    const total = base + dx;
    const side = total < 0 ? 1 : total > 0 ? -1 : 0;
    const pane = side ? c.neighbour(side) : null;
    if (pane) applyTurn(total, { pane, side }, w);
    else applyTurn(rubber(total), null, w);
  };
  // the release (UIState.settle): a moving finger says the way, a still one the distance; the spring 0.35 / 0.9 carries the
  // neighbour to the pane's place, and at its end the roles swap where the pages stand
  const turnEnd = (ended, vx, w) => {
    const total = turnX, n = turnN;
    let goes = false;
    if (ended && n) goes = Math.abs(vx) > 10 ? (n.side > 0 ? total < 0 && vx < 0 : total > 0 && vx > 0) : Math.abs(total) > w / 2;
    const side = goes ? n.side : 0;
    turnAnim?.cancel();
    const cancel = spring(total, -side * w, { response: 0.35, damping: 0.9 }, (x) => applyTurn(x, n, w), () => {
      turnAnim = null;
      if (side) cfg().turned(n.pane);
      releaseTurn();
    });
    turnAnim = { cancel };
  };
  // a stroke's start cuts a settle still running where it stands (UIState.beginStroke): that place is the stroke's base
  const turnBegin = () => {
    if (!turnAnim) return 0;
    turnAnim.cancel();
    turnAnim = null;
    return turnX;
  };

  const onDown = (e) => {
    if (st || (e.pointerType === "mouse" && e.button !== 0)) return;
    const c = cfg();
    const base = { id: e.pointerId, x0: e.clientX, y0: e.clientY, validated: false, samples: [] };
    if (c.drawerOpen || drawerAnim) {
      // the dimmed page: its stroke drags the drawer back, its tap closes it (the dim's own click)
      if (c.drawerOpen && e.target.closest?.(".drawer-dim")) st = { ...base, kind: "dim" };
      return;
    }
    if (e.clientX <= EDGE && c.edgeAllowed()) { st = { ...base, kind: "edge" }; return; }
    const list = c.list;
    if (!list || !list.contains(e.target) || !c.turnAllowed()) return;
    const r = list.getBoundingClientRect();
    const ex = turnEdge(r.width);
    if (e.clientX - r.left < ex || r.right - e.clientX < ex) return;   // the rows' and the drawer's
    if (refuses(e.target, list)) return;
    st = { ...base, kind: "tabs", w: r.width };
  };

  const begin = (dx) => {
    const c = cfg();
    if (st.kind === "edge") { st.road = "drawer"; st.base = 0; }
    else if (st.kind === "dim") { st.road = "drawer"; st.base = width(); }
    else if (dx > 0 && c.atRowStart()) { st.road = "drawer"; st.base = 0; }   // the row's left end opens the drawer
    else {
      const step = dx < 0 ? 1 : -1;
      if (c.folderBeside(step)) { st.road = "folder"; st.step = step; }    // the chats page turns its folders first
      else { st.road = "turn"; st.base = turnBegin(); }
    }
    if (st.road === "drawer") { drawerAnim?.cancel(); drawerAnim = null; c.drawerMoving(true); }
    document.documentElement.classList.add("stroking");
  };

  const onMove = (e) => {
    if (!st || e.pointerId !== st.id) return;
    if (e.pointerType === "mouse" && !(e.buttons & 1)) { onUp(e, false); return; }
    const dx = e.clientX - st.x0, dy = e.clientY - st.y0;
    if (!st.validated) {
      // the reference's validation (MTTabPan.touchesMoved): flat at once when the first points run flat, down at once when they
      // run down, the dominant way after ten points
      const ax = Math.abs(dx), ay = Math.abs(dy);
      if (Math.hypot(ax, ay) > 10) { if (ax >= ay) st.validated = true; else { st = null; return; } }
      else if (ay > 2 && ay > ax * 2) { st = null; return; }
      else if (ax > 2 && ay * 2 < ax) st.validated = true;
      if (!st.validated) return;
      if (st.kind === "edge" && dx <= 0) { st = null; return; }   // the edge's stroke runs right
      try { cfg().shell?.setPointerCapture(e.pointerId); } catch { /* the stroke still runs where the pointer goes */ }
      begin(dx);
    }
    e.preventDefault();
    st.samples.push({ t: performance.now(), x: dx });
    if (st.samples.length > 12) st.samples.shift();
    if (st.road === "drawer") applyDrawer(st.base + dx);
    else if (st.road === "turn") turnMove(st.base, dx, st.w);
  };

  const onUp = (e, ended = true) => {
    if (!st || e.pointerId !== st.id) return;
    const s = st;
    st = null;
    if (!s.validated) return;
    document.documentElement.classList.remove("stroking");
    swallowUntil = performance.now() + 400;
    const dx = e.clientX - s.x0;
    const v = speed(s.samples);
    if (s.road === "drawer") {
      const open = ended && (Math.abs(v) > 300 ? v > 0 : drawerFrom() > width() / 2);
      settleDrawer(open, v);
    } else if (s.road === "folder") {
      const goes = ended && (Math.abs(v) > 10 ? (s.step > 0 ? v < 0 : v > 0) : Math.abs(dx) > s.w / 3);
      if (goes) cfg().folderTurned(s.step);
    } else if (s.road === "turn") {
      turnEnd(ended, v, s.w);
    }
  };

  // THE TOUCHPAD'S SIDEWAYS STROKE: the two fingers' deltas move the pages as a finger does, the stroke ending when they rest
  const onWheel = (e) => {
    if (Math.abs(e.deltaX) <= Math.abs(e.deltaY) || st) return;
    const c = cfg();
    const list = c.list;
    if (!wheel) {
      if (c.drawerOpen || drawerAnim || !list || !list.contains(e.target) || !c.turnAllowed() || refuses(e.target, list)) return;
      wheel = { x: 0, samples: [], w: list.getBoundingClientRect().width, road: null };
    }
    e.preventDefault();
    wheel.x -= e.deltaX * (e.deltaMode === 1 ? 33 : 1);
    wheel.samples.push({ t: performance.now(), x: wheel.x });
    if (wheel.samples.length > 12) wheel.samples.shift();
    if (!wheel.road) {
      if (wheel.x > 0 && c.atRowStart()) { wheel.road = "drawer"; drawerAnim?.cancel(); drawerAnim = null; c.drawerMoving(true); }
      else if (c.folderBeside(wheel.x < 0 ? 1 : -1)) { wheel.road = "folder"; wheel.step = wheel.x < 0 ? 1 : -1; }
      else { wheel.road = "turn"; wheel.base = turnBegin(); }
    }
    if (wheel.road === "drawer") applyDrawer(wheel.x);
    else if (wheel.road === "turn") turnMove(wheel.base, wheel.x, wheel.w);
    clearTimeout(wheel.idle);
    wheel.idle = setTimeout(() => {
      const w = wheel;
      wheel = null;
      // the fingers' speed as they left the pad: the last tenth of a second of the stroke
      const v = speed(w.samples, w.samples[w.samples.length - 1].t);
      if (w.road === "drawer") settleDrawer(Math.abs(v) > 300 ? v > 0 : drawerFrom() > width() / 2, v);
      else if (w.road === "folder") {
        if (Math.abs(v) > 10 ? (w.step > 0 ? v < 0 : v > 0) : Math.abs(w.x) > w.w / 3) cfg().folderTurned(w.step);
      } else if (w.road === "turn") turnEnd(true, v, w.w);
    }, 140);
  };

  const onClick = (e) => {
    if (performance.now() < swallowUntil) { e.stopPropagation(); e.preventDefault(); swallowUntil = 0; }
  };

  const attach = () => {
    const shell = cfg().shell;
    if (!shell) return undefined;
    const cancel = (e) => onUp(e, false);
    shell.addEventListener("pointerdown", onDown, true);
    shell.addEventListener("pointermove", onMove, true);
    shell.addEventListener("pointerup", onUp, true);
    shell.addEventListener("pointercancel", cancel, true);
    shell.addEventListener("wheel", onWheel, { passive: false });
    window.addEventListener("click", onClick, true);
    const resize = () => { if (drawerX != null && !drawerAnim) applyDrawer(cfg().drawerOpen ? width() : 0); };
    window.addEventListener("resize", resize);
    return () => {
      shell.removeEventListener("pointerdown", onDown, true);
      shell.removeEventListener("pointermove", onMove, true);
      shell.removeEventListener("pointerup", onUp, true);
      shell.removeEventListener("pointercancel", cancel, true);
      shell.removeEventListener("wheel", onWheel);
      window.removeEventListener("click", onClick, true);
      window.removeEventListener("resize", resize);
      drawerAnim?.cancel();
      turnAnim?.cancel();
    };
  };

  /** A tap, a key or a row of the drawer (MontanaDrawerController.setOpen): the same spring, no speed. */
  const animateDrawer = (open) => {
    const target = open ? width() : 0;
    if (drawerAnim?.target === target) return;
    if (drawerX == null && !drawerAnim && !st) {
      // React's class already stands where the drawer goes: the page starts from where it stood before
      applyDrawer(open ? 0 : width());
    }
    settleDrawer(open, 0);
  };

  return { attach, animateDrawer };
}

/**
 * THE DRAWER ALWAYS GIVES UNDER THE FINGER (iOS MontanaSideDrawer: its ScrollView bounces always, the column laid at least a
 * screen tall -- ContentView.swift 1753-1760 -- so the drawer springs under the finger even when its rows fit). Windows draws no
 * bounce of its own, so it is drawn here: past either end the column follows the touchpad, the wheel, the touch or the pen with
 * UIScrollView's resistance -- (1 − 1 / (x · 0.55 / d + 1)) · d, d the column's height -- and springs home once let go; a touch
 * or a pen scrolls the column itself, with the platform's deceleration (0.998 a millisecond), and a fling that reaches an end
 * carries its speed into the bounce. The column is moved by --bounce (CSS: .drawer > *).
 */
export function useBounce(ref, on) {
  useEffect(() => {
    const el = ref.current;
    if (!el || !on) return undefined;
    let pull = 0, shown = 0, anim = null, idle = 0, drag = null, fling = 0;
    const d = () => Math.max(1, el.clientHeight);
    const band = (x) => Math.sign(x) * (1 - 1 / ((Math.abs(x) * 0.55) / d() + 1)) * d();
    const show = (y) => {
      shown = y;
      if (Math.abs(y) < 0.01) el.style.removeProperty("--bounce");
      else el.style.setProperty("--bounce", `${y}px`);
    };
    const stop = () => { anim?.(); anim = null; cancelAnimationFrame(fling); fling = 0; };
    const home = (velocity = 0) => {
      stop();
      pull = 0;
      anim = spring(shown, 0, { response: 0.4, damping: 1, velocity }, show, () => { anim = null; show(0); });
    };
    const room = () => Math.max(0, el.scrollHeight - el.clientHeight);
    // the column moved by dy (down positive, as the finger): the scroll takes it while it can, the band takes the rest
    const move = (dy) => {
      if (pull !== 0) {
        const was = pull;
        pull += dy;
        if (Math.sign(pull) !== Math.sign(was)) { dy = pull; pull = 0; show(0); } else { show(band(pull)); return; }
      }
      const top = el.scrollTop - dy;
      if (top < 0) { el.scrollTop = 0; pull = -top; show(band(pull)); }
      else if (top > room()) { el.scrollTop = room(); pull = room() - top; show(band(pull)); }
      else el.scrollTop = top;
    };
    const wheel = (e) => {
      if (Math.abs(e.deltaX) > Math.abs(e.deltaY) || e.ctrlKey) return;
      const dy = -e.deltaY * (e.deltaMode === 1 ? 33 : 1);
      const atTop = el.scrollTop <= 0, atEnd = el.scrollTop >= room() - 1;
      if (pull === 0 && !anim && !((dy > 0 && atTop) || (dy < 0 && atEnd))) return;   // the platform's own scroll
      e.preventDefault();
      stop();
      if (pull === 0 && shown !== 0) pull = shown;
      move(dy);
      clearTimeout(idle);
      idle = setTimeout(() => { if (pull !== 0) home(); }, 120);
    };
    const down = (e) => {
      if (e.pointerType === "mouse" || drag) return;
      stop();
      if (shown !== 0) pull = shown;
      drag = { id: e.pointerId, y: e.clientY, x: e.clientX, live: false, samples: [] };
    };
    const moveP = (e) => {
      if (!drag || e.pointerId !== drag.id) return;
      const dy = e.clientY - drag.y;
      if (!drag.live) {
        if (Math.abs(dy) < 10 && Math.abs(e.clientX - drag.x) < 10) return;
        if (Math.abs(dy) < Math.abs(e.clientX - drag.x)) { drag = null; return; }
        drag.live = true;
        try { el.setPointerCapture(e.pointerId); } catch { /* the column still follows */ }
      }
      drag.y = e.clientY;
      drag.samples.push({ t: performance.now(), x: e.clientY });
      if (drag.samples.length > 12) drag.samples.shift();
      move(dy);
    };
    const up = (e) => {
      if (!drag || e.pointerId !== drag.id) return;
      const g = drag;
      drag = null;
      if (!g.live) return;
      const v = speed(g.samples);
      if (pull !== 0) { home(0); return; }
      // the platform's deceleration; an end reached mid-flight takes the rest of the speed into the bounce
      let vel = v, last = performance.now();
      const step = (now) => {
        const dt = Math.min(50, now - last);
        last = now;
        vel *= 0.998 ** dt;
        const before = el.scrollTop;
        const top = before - (vel * dt) / 1000;
        if (top < 0 || top > room()) {
          el.scrollTop = top < 0 ? 0 : room();
          fling = 0;
          anim = spring(0, 0, { response: 0.4, damping: 1, velocity: vel }, show, () => { anim = null; show(0); });
          return;
        }
        el.scrollTop = top;
        if (Math.abs(vel) < 10) { fling = 0; return; }
        fling = requestAnimationFrame(step);
      };
      if (Math.abs(v) > 50) fling = requestAnimationFrame(step);
    };
    el.addEventListener("wheel", wheel, { passive: false });
    el.addEventListener("pointerdown", down);
    el.addEventListener("pointermove", moveP);
    el.addEventListener("pointerup", up);
    el.addEventListener("pointercancel", up);
    return () => {
      stop();
      clearTimeout(idle);
      show(0);
      el.removeEventListener("wheel", wheel);
      el.removeEventListener("pointerdown", down);
      el.removeEventListener("pointermove", moveP);
      el.removeEventListener("pointerup", up);
      el.removeEventListener("pointercancel", up);
    };
  }, [on]);
}
