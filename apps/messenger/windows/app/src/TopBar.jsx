import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { GLYPHS } from "./glyphs.js";
import logo from "./assets/logo.png";
import { t } from "./strings.js";

// THE TIME PANEL of iOS Montana 2251 (MontanaChatsList.swift 370-545, MontanaShapes.swift 85-96, ContentView.swift 1482-1520):
// one plate, 60 high and 14 within its sides, seven equal slots -- the drawer, the contacts, the calls, the logo always in the
// centre, the chats, the last of the music and the gallery, the globe; one puck under the page's slot; a red count at a glyph's
// top-trailing corner, 10 out and 4 up; folded, the plate is the logo alone (88 wide) and a tap on it unfolds the panel, the page
// staying; the choice is kept (@AppStorage timePanelOpen). A glyph pressed shrinks to 0.88 at 0.7 (MTBarGlyphStyle).
export const SLOTS = ["drawer", "contacts", "calls", "logo", "chats", "media", "globe"];
const PANE_SLOT = { chats: 4, contacts: 1, calls: 2, music: 5, gallery: 5, feed: 3, vpn: 6 };

export function Glyph({ name, size = 26, color }) {
  const g = GLYPHS[name];
  return (
    <svg width={size} height={size} viewBox={`0 0 ${g.box[0]} ${g.box[1]}`} style={{ color, display: "block" }} aria-hidden="true">
      {g.paths.map((p, i) => (
        <path key={i} d={p.d} fill={p.fill} stroke={p.stroke} strokeWidth={p.strokeWidth || undefined}
              strokeLinecap={p.cap} strokeLinejoin={p.join} fillRule={p.evenodd ? "evenodd" : undefined} />
      ))}
    </svg>
  );
}

/** The platform's red counter (MTCountBadge): a 20 capsule, 13 semibold white, 99+; nothing when there is nothing. */
function CountBadge({ count }) {
  if (!count) return null;
  return <span className="count-badge">{count > 99 ? "99+" : count}</span>;
}

function readOpen() {
  try { return localStorage.getItem("timePanelOpen") !== "0"; } catch { return true; }
}
const PANEL = "montana-panel";
/** THE PANEL FOLDED OR UNFOLDED (iOS turnPanel): the coin pulled on a list turns it, the logo or the hairline unfolds it; kept. */
export function turnPanel(open, by = "logo") {
  try { localStorage.setItem("timePanelOpen", open ? "1" : "0"); } catch { /* the choice is only kept where storage is */ }
  invoke("trace", { line: `panel open=${open ? 1 : 0} by=${by}` }).catch(() => {});
  window.dispatchEvent(new CustomEvent(PANEL, { detail: open }));
}
/** Whether the panel stands unfolded, heard again whenever it turns. */
export function usePanelOpen() {
  const [open, setOpen] = useState(readOpen);
  useEffect(() => {
    const hear = (e) => setOpen(e.detail);
    window.addEventListener(PANEL, hear);
    return () => window.removeEventListener(PANEL, hear);
  }, []);
  return open;
}

/** The crossed speaker (SF speaker.slash): the system refused the banners. */
function SpeakerSlash({ size = 26, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ color, display: "block" }} aria-hidden="true">
      <path d="M4 9.2h3.2L12 5v14l-4.8-4.2H4z" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinejoin="round" />
      <path d="M15.5 9.5c.9.7 1.4 1.6 1.4 2.5s-.5 1.8-1.4 2.5M18 7c1.5 1.3 2.4 3 2.4 5s-.9 3.7-2.4 5" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" />
      <path d="M3 3l18 18" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" />
    </svg>
  );
}

export default function TopBar({ pane, onPane, unread = 0, missed = 0, mediaIsMusic = true }) {
  const open = usePanelOpen();
  const slots = useRef([]);
  const plate = useRef(null);
  const [puck, setPuck] = useState(null);
  const home = PANE_SLOT[pane];
  const turn = (o) => turnPanel(o, "logo");
  // THE GLOBE READS THE NODE ITSELF (iOS MTBarGlobe): green while a node is held, red once the doors were knocked and none is
  const [lamp, setLamp] = useState({ up: false, known: false });
  useEffect(() => {
    let gone = false;
    const look = () => invoke("node_lamp").then((l) => { if (!gone) setLamp(l); }).catch(() => {});
    look();
    const id = setInterval(look, 2000);
    return () => { gone = true; clearInterval(id); };
  }, []);
  // THE FIRST SLOT SAYS WHAT STANDS IN THE WAY (iOS slot 0): the banners refused, then the copy with contacts kept nowhere, else
  // the drawer's grid; read again at every page
  const [first, setFirst] = useState("");
  useEffect(() => { invoke("bar_first").then(setFirst).catch(() => {}); }, [pane]);
  const network = lamp.up ? "up" : lamp.known ? "down" : "unknown";

  // the puck stands under the pane's slot, measured as drawn (iOS MTBarSlotKey): folded, only the logo has a place
  useLayoutEffect(() => {
    const el = slots.current[home];
    if (home == null || !el || !plate.current || (!open && home !== 3)) { setPuck(null); return; }
    const a = plate.current.getBoundingClientRect();
    const b = el.getBoundingClientRect();
    setPuck({ left: b.left - a.left - plate.current.clientLeft + 3, width: b.width - 6 });   // MTBarPuck().padding(.horizontal, 3)
  }, [home, open]);

  // THE DRAWER STAYS ONE STROKE AWAY (iOS MontanaDrawerHost: the screen's left edge): while the first slot says what stands in the way,
  // its right button -- or a stroke from the window's left edge (App) -- still opens the drawer
  const slot = (i, label, onTap, glyph, badge) => (
    <button key={i} ref={(el) => (slots.current[i] = el)} className={`bar-slot${i === 3 ? " logo-slot" : ""}`}
            aria-label={label} onClick={onTap} tabIndex={open || i === 3 ? 0 : -1}
            onContextMenu={i === 0 ? (e) => { e.preventDefault(); onPane("drawer"); } : undefined}>
      <span className="glyph-box">{glyph}{open && <CountBadge count={badge} />}</span>
    </button>
  );
  const ink = "var(--bar-glyph)";
  const lampInk = network === "up" ? "var(--green)" : network === "down" ? "var(--red)" : "var(--lamp-unknown)";

  return (
    <div className="time-panel">
      <div ref={plate} className={`bar-plate${open ? "" : " folded"}`}>
        {puck && <span className="bar-puck" style={{ transform: `translateX(${puck.left}px)`, width: puck.width }} />}
        {slot(0, first === "notifications" ? t("Notifications are off") : first === "keeping" ? t("Keep my copy with my contacts") : t("App Library"),
          () => onPane(first || "drawer"),
          first === "notifications" ? <SpeakerSlash size={26} color={ink} /> : <Glyph name={first === "keeping" ? "peopleSlash" : "drawer"} size={26} color={ink} />)}
        {slot(1, t("Contacts"), () => onPane("contacts"), <Glyph name="contacts" size={26} color={ink} />)}
        {/* the missed calls' count is said with the slot's name, as the badge shows it */}
        {slot(2, missed && open ? `${t("Calls")}: ${missed}` : t("Calls"), () => onPane("calls"), <Glyph name="calls" size={26} color={ink} />, missed)}
        {slot(3, "Montana", () => (open ? onPane("feed") : turn(true)),
          <span className="logo-plate"><img src={logo} alt="" />{!open && <CountBadge count={unread + missed} />}</span>)}
        {slot(4, t("Chats"), () => onPane("chats"), <Glyph name="chats" size={24} color={ink} />, unread)}
        {slot(5, mediaIsMusic ? t("Music") : t("Gallery"), () => onPane(mediaIsMusic ? "music" : "gallery"),
          <Glyph name={mediaIsMusic ? "music" : "gallery"} size={26} color={ink} />)}
        {slot(6, network === "up" ? t("Connected") : t("Disconnected"), () => onPane("vpn"), <Glyph name="globe" size={26} color={lampInk} />)}
      </div>
    </div>
  );
}
