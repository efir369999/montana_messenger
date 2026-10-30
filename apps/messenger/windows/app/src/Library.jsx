import { useEffect, useState } from "react";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { Page, Section } from "./Settings.jsx";
import { drawerWidth } from "./turn.js";
import logo from "./assets/logo.png";
import knight from "./assets/ios/Chesswn.png";
import goldAtlas from "./assets/library_gold.png";
import nativeAtlas from "./assets/library_native.png";
import vpnGlobe from "./assets/vpn_globe.png";

/** THE APPLICATIONS' ICONS (iOS MTApplicationLibrary: MTLibraryIconStyle, MTApplicationIcon, MTLibraryIconStyleView): three
 *  styles -- the white glyphs of the 1990 drawer (the default), «Montana OS» and «Gold style», each a tile of the author's own
 *  atlas, unchanged -- and the drawer's view, the list (the default) or the icons' grid. The choice is this machine's. */
export const STYLES = [["white", "White icons"], ["native", "Montana OS"], ["gold", "Gold style"]];
const STYLE = "appLibraryIconStyle", VIEW = "appLibraryIcons", PINS = "appLibraryPins";
const read = (k, d) => { try { return localStorage.getItem(k) ?? d; } catch { return d; } };
const keep = (k, v) => {
  try { localStorage.setItem(k, v); } catch { /* the choice lives while the window does */ }
  window.dispatchEvent(new Event("montana-library"));
};
export const readStyle = () => (STYLES.some(([k]) => k === read(STYLE, "")) ? read(STYLE, "") : "white");
export const readGrid = () => read(VIEW, "false") === "true";
export const readPins = () => new Set(read(PINS, "chats,contacts,calls,feed").split(",").filter(Boolean));

/** The library's choice as it stands, heard again whenever a page changes it. */
export function useLibrary() {
  const [v, setV] = useState(() => ({ style: readStyle(), grid: readGrid(), pins: readPins() }));
  useEffect(() => {
    const hear = () => setV({ style: readStyle(), grid: readGrid(), pins: readPins() });
    window.addEventListener("montana-library", hear);
    return () => window.removeEventListener("montana-library", hear);
  }, []);
  return v;
}
export function pin(app, pins) {
  const next = new Set(pins);
  if (next.has(app)) next.delete(app); else next.add(app);
  keep(PINS, [...next].join(","));
}

/** The applications' titles (iOS MTApplication.title), the words of the drawer. */
export const TITLES = { contacts: "Contacts", calls: "Calls", feed: "Wall of Thoughts", chats: "Chats", music: "Music", gallery: "Gallery",
                        chess: "Chess", wallet: "TimeCoin", vpn: "VPN wall", mesh: "Mesh wall", p2p: "P2P wall", card: "Business card",
                        passwords: "Passwords", settings: "Settings" };

/** Each application's tile in the author's atlases (iOS artworkIndex): -1 -- none, its white glyph in every style. */
const ART = { contacts: 0, calls: 1, chats: 2, feed: 4, wallet: -1, card: 6, music: 7, gallery: 8, chess: 9, vpn: 10, mesh: 10, p2p: 10,
              settings: 11, passwords: -1 };
const GLYPH = { contacts: "personCircle", calls: "calls", chats: "chats", music: "music", gallery: "gallery", chess: "chess", wallet: "wallet",
                vpn: "globe", mesh: "antenna", p2p: "globe", card: "card", passwords: "key", settings: "settings" };

/** ONE APPLICATION'S ICON at its side, in the style chosen (or the one given): the white glyph drawn for a 30 mark and scaled;
 *  «Montana OS» the atlas of 1254 in windows of 300; gold the atlas of 1122x1402 in windows of 234, rounded 0.21, the logo's
 *  badge where it can be read (48 and more). */
export function AppIcon({ app, side = 30, style }) {
  const s = style || readStyle(), index = ART[app] ?? -1;
  if (index === -1 || s === "white") {
    const unit = side / 30;
    return (
      <span className="app-icon" style={{ width: side, height: side }}>
        {app === "feed" ? <span className="feed-mark" style={{ width: 26 * unit, height: 26 * unit }}><img src={logo} alt="" style={{ width: 16 * unit, height: 16 * unit }} /></span>
          // the chess's mark is its own white knight (iOS MTChessIcon: the asset Chesswn), never a die
          : app === "chess" ? <img src={knight} alt="" style={{ width: 26 * unit, height: 26 * unit, objectFit: "contain" }} />
          // the VPN wall's own globe on its stand (iOS MontanaVPNGlyph: the template image MontanaVPNGlobe, white)
          : app === "vpn" ? <span className="vpn-globe" style={{ width: 26 * unit, height: 26 * unit, WebkitMaskImage: `url(${vpnGlobe})`, maskImage: `url(${vpnGlobe})` }} />
          : <Glyph name={GLYPH[app]} size={26 * unit} color="#fff" />}
      </span>
    );
  }
  if (s === "gold") {
    const k = side / 234, x = [48, 312, 576, 840][index % 4], y = [250, 547, 839][Math.floor(index / 4)];
    return (
      <span className="app-icon app-tile" style={{ width: side, height: side, borderRadius: side * 0.21, backgroundImage: `url(${goldAtlas})`,
                                              backgroundSize: `${1122 * k}px ${1402 * k}px`, backgroundPosition: `${-x * k}px ${-y * k}px` }}>
        {side >= 48 && <img className="app-tile-logo" src={logo} alt="" style={{ width: side * 0.3, height: side * 0.3, padding: side * 0.025 }} />}
      </span>
    );
  }
  const k = side / 300, x = [29, 330, 626, 931][index % 4], y = [130, 482, 795][Math.floor(index / 4)];
  return <span className="app-icon app-tile" style={{ width: side, height: side, backgroundImage: `url(${nativeAtlas})`,
                                                      backgroundSize: `${1254 * k}px ${1254 * k}px`, backgroundPosition: `${-x * k}px ${-y * k}px` }} />;
}

/** The library's groups (iOS MTLibraryGroup), each application's title sorted within its own. */
const GROUPS = [["communication", "Communication", ["contacts", "calls", "chats"]],
                ["montana", "Montana", ["feed", "card", "wallet", "vpn", "mesh", "p2p"]],
                ["media", "Media", ["music", "gallery", "chess"]], ["utilities", "Utilities", ["settings", "passwords"]]];

/** THE ICONS' GRID OF THE DRAWER (iOS MTLibrarySearch, icons): the favourites first, then each group; a tile opens its page,
 *  its menu opens or pins it (iOS MTLibraryCommand). */
export function LibraryGrid({ counts, onOpen, titles = TITLES }) {
  const { style, pins } = useLibrary();
  const [menu, setMenu] = useState(null);
  // the columns the drawer holds (iOS MontanaSideDrawer: max(1, Int((width − 16) / 104)), the drawer round(0.78 × the window), at most 480 -- turn.js drawerWidth)
  const [cols, setCols] = useState(() => Math.max(1, Math.floor((drawerWidth() - 16) / 104)));
  useEffect(() => {
    const on = () => setCols(Math.max(1, Math.floor((drawerWidth() - 16) / 104)));
    window.addEventListener("resize", on);
    return () => window.removeEventListener("resize", on);
  }, []);
  const sorted = (apps) => [...apps].sort((a, b) => t(titles[a]).localeCompare(t(titles[b])));
  const all = GROUPS.flatMap(([, , apps]) => apps);
  const sections = [["favorites", "Favorites", sorted(all.filter((a) => pins.has(a)))],
                    ...GROUPS.map(([id, title, apps]) => [id, title, sorted(apps.filter((a) => !pins.has(a)))])].filter(([, , apps]) => apps.length);
  return (
    <div className="library-grid" onClick={() => setMenu(null)}>
      {sections.map(([id, title, apps]) => (
        <div key={id} className="library-section">
          <div className="library-head">{title === "Montana" ? title : t(title)}</div>
          <div className="library-tiles" style={{ gridTemplateColumns: `repeat(${cols}, 1fr)` }}>
            {apps.map((a) => (
              <button key={a} className="library-tile" aria-label={t(titles[a])} onClick={() => onOpen(a)}
                      onContextMenu={(e) => { e.preventDefault(); e.stopPropagation(); setMenu({ app: a, x: e.clientX, y: e.clientY }); }}>
                <span className="library-icon"><AppIcon app={a} side={62} style={style} />{counts[a] > 0 && <span className="count-badge">{counts[a] > 99 ? "99+" : counts[a]}</span>}</span>
                <span className="library-title">{t(titles[a])}</span>
              </button>
            ))}
          </div>
        </div>
      ))}
      {/* THE TILE'S MENU (iOS MTLibraryCommand): «Open» with arrow.up.forward.app, «Pin» / «Unpin» with pin / pin.slash */}
      {menu && (
        <div className="letter-menu library-menu" style={{ left: Math.min(menu.x, window.innerWidth - 250), top: Math.min(menu.y, window.innerHeight - 110) }}
             role="menu" onClick={(e) => e.stopPropagation()}>
          <div className="menu-rows">
            <button className="menu-row" role="menuitem" onClick={() => { setMenu(null); onOpen(menu.app); }}><span>{t("Open")}</span><OpenGlyph /></button>
            <button className="menu-row" role="menuitem" onClick={() => { setMenu(null); pin(menu.app, pins); }}>
              <span>{t(pins.has(menu.app) ? "Unpin" : "Pin")}</span><Glyph name={pins.has(menu.app) ? "pinSlash" : "pin"} size={18} />
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/** SF arrow.up.forward.app: the rounded square with the arrow leaving its corner. */
const OpenGlyph = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true">
    <path d="M13 4H7.5A3.5 3.5 0 0 0 4 7.5v9A3.5 3.5 0 0 0 7.5 20h9a3.5 3.5 0 0 0 3.5-3.5V11" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
    <path d="M11 13l9-9M14.5 4H20v5.5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

/** «APPLICATION ICONS» (iOS MTLibraryIconStyleView): the drawer's view, then each style as a card of its own icons. */
const PREVIEW = ["contacts", "calls", "chats", "feed", "wallet", "card", "music", "gallery", "chess", "vpn", "mesh", "p2p", "settings"];
export function LibraryPage({ onClose, titles = TITLES }) {
  const { style, grid } = useLibrary();
  return (
    <Page title={t("Application icons")} onClose={onClose} back>
      <Section head={t("View")} foot={t("Applications show as a list, or as a grid of icons.")}>
        <div className="slow-steps" role="radiogroup" aria-label={t("View")}>
          {[[false, "List"], [true, "Icons"]].map(([g, word]) => (
            <button key={word} role="radio" aria-checked={grid === g} className={"slow-step" + (grid === g ? " on" : "")}
                    onClick={() => keep(VIEW, String(g))}>{t(word)}</button>
          ))}
        </div>
      </Section>
      {STYLES.map(([k, word]) => (
        <Section key={k}>
          <button className="library-card" role="radio" aria-checked={style === k} aria-label={k === "native" ? word : t(word)} onClick={() => keep(STYLE, k)}>
            <span className="library-card-head"><b>{k === "native" ? word : t(word)}</b><span className={"tick" + (style === k ? " on" : "")}>{style === k ? "✓" : ""}</span></span>
            <span className="library-card-grid">
              {PREVIEW.map((a) => (
                <span key={a} className="library-card-app"><AppIcon app={a} side={56} style={k} /><span>{t(titles[a])}</span></span>
              ))}
            </span>
          </button>
        </Section>
      ))}
    </Page>
  );
}
