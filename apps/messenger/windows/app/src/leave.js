import { useEffect, useRef } from "react";

/** THE WAY BACK WITHOUT A FINGER (iOS: the left edge's stroke, a sheet pulled down, a menu tapped away): on Windows Esc, the mouse's
 *  back button and Alt+← take the topmost layer away -- a menu or an alert first (Esc alone), then the newest page, sheet, viewer or
 *  drawer that stands -- one layer a press, never the one under it. Nothing is drawn for it: the screen stays iOS's. */
const stack = [];

/** The layer standing while `on`: `leave` is what its own back mark does. */
export function useLeave(leave, on = true) {
  const fn = useRef(leave);
  fn.current = leave;
  useEffect(() => {
    if (!on) return undefined;
    const entry = { fn };
    stack.push(entry);
    return () => {
      const i = stack.indexOf(entry);
      if (i >= 0) stack.splice(i, 1);
    };
  }, [on]);
}

function back(e, shades) {
  if (shades) {
    // a menu's or an alert's shade closes as a tap beside it closes it
    const shade = [...document.querySelectorAll(".menu-shade, .alert-shade")].pop();
    if (shade) { e.preventDefault(); shade.click(); return; }
  }
  const top = stack[stack.length - 1];
  if (top) { e.preventDefault(); top.fn.current(); }
}

if (typeof window !== "undefined") {
  window.addEventListener("keydown", (e) => {
    if (e.defaultPrevented || e.repeat) return;
    if (e.key === "Escape") back(e, true);
    else if (e.altKey && e.key === "ArrowLeft") back(e, false);
  });
  // the mouse's own back button (XButton1)
  window.addEventListener("mouseup", (e) => { if (e.button === 3) back(e, false); });
}
