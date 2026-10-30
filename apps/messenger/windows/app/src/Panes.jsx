import { Fragment, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t, locale, dayWord } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { Face, SAVED, SelfFace, chatName, seenText, useChanged } from "./Chats.jsx";
import { BIG, useFile } from "./Media.jsx";
import * as player from "./player.js";
import { TrackRow } from "./PlayerBar.jsx";
import { AppIcon, LibraryGrid, useLibrary } from "./Library.jsx";
import { callTo } from "./Call.jsx";
import { useBounce } from "./turn.js";

/** THE DRAWER (iOS MontanaSideDrawer, ContentView.swift 1560-1742): under the page; my face at the head opens my page; the
 *  applications in the iOS order; Settings at the foot with the version. A desktop window is wide: the drawer keeps to 360. */
export const APPS = [
  ["contacts", "Contacts", "personCircle"], ["calls", "Calls", "calls"], ["feed", "Wall of Thoughts", null],
  ["chats", "Chats", "chats"], ["music", "Music", "music"], ["gallery", "Gallery", "gallery"], ["chess", "Chess", "chess"],
  ["wallet", "TimeCoin", "wallet"], ["vpn", "VPN wall", "globe"], ["mesh", "Mesh wall", "antenna"], ["p2p", "P2P wall", "globe"],
  ["card", "Business card", "card"], ["passwords", "Passwords", "key"],
];

/** THE FACES AT THE HEAD OF THE DRAWER (iOS the second identity checklist): the person seated, every person of this computer
 *  waiting on the shelf -- a touch seats them -- and the plus that makes one more person beside those that stand. */
export function Drawer({ open, shown = open, person, counts = {}, onClose, onApp, onMe, onSettings, version, parked = [], onSeat, onAdd }) {
  const { style, grid } = useLibrary();   // the icons' style and the drawer's view (Appearance → Application icons)
  const column = useRef(null);
  useBounce(column, open);   // the column always gives under the finger (iOS .scrollBounceBehavior(.always))
  // drawn while it moves (shown), read and touched only while it stands open: a drawer on its way home answers nothing
  return (
    <aside className={"drawer" + (shown ? " open" : "")} aria-hidden={!open} inert={!open || undefined} ref={column}>
      <div className="drawer-faces">
        <button className="drawer-face me" onClick={onMe} aria-label={person.name}>
          <SelfFace name={person.name} version={person.face} size={48} />
          <span className="drawer-face-name">{person.name}</span>
        </button>
        {parked.map((s) => (
          <button key={s.id} className="drawer-face" onClick={() => onSeat(s.id)} aria-label={s.name || "Montana"}>
            <div className="self-face" style={{ width: 48, height: 48, fontSize: 19 }}>
              {s.face ? <img src={`data:image/jpeg;base64,${s.face}`} alt="" className="face-photo" /> : (s.glyph || "M").toUpperCase()}
            </div>
            <span className="drawer-face-name">{s.name}</span>
          </button>
        ))}
        <button className="drawer-face" onClick={onAdd} aria-label={t("Choose how to sign in")}>
          <div className="self-face plus" style={{ width: 48, height: 48 }}><Glyph name="plus" size={24} color="#fff" /></div>
          <span className="drawer-face-name" />
        </button>
      </div>
      {grid ? (
        <div className="drawer-rows grid">
          <LibraryGrid counts={counts} onOpen={(k) => (k === "settings" ? onSettings() : onApp(k))} />
          <div className="drawer-version center">{version}</div>
        </div>
      ) : (
        <div className="drawer-rows">
          {APPS.map(([k, title]) => (
            <button key={k} className="drawer-row" onClick={() => onApp(k)}>
              <span className="drawer-icon"><AppIcon app={k} side={30} style={style} /></span>
              <span className="drawer-title">{t(title)}</span>
              {counts[k] > 0 && <span className="count-badge static">{counts[k] > 99 ? "99+" : counts[k]}</span>}
            </button>
          ))}
          <div className="grow" />
          <button className="drawer-row" onClick={onSettings}>
            <span className="drawer-icon"><AppIcon app="settings" side={30} style={style} /></span>
            <span className="drawer-title">{t("Settings")}</span>
          </button>
          <div className="drawer-version">{version}</div>
        </div>
      )}
      {open && <div className="drawer-close" onClick={onClose} />}
    </aside>
  );
}

/** A part of iOS Montana that Windows does not have yet: said plainly, under its own name. */
export function NotYet({ title }) {
  return (
    <div className="empty-pane">
      <div className="empty-title">{t(title)}</div>
      <div className="empty-text">{t("This part of Montana is not on Windows yet.")}</div>
    </div>
  );
}

/** CONTACTS (iOS ContactsTabView): the people of my conversations, by name; a tap writes to them, the menu shows their page.
 *  (Presence, pins, archive and the book's own cards are not on Windows yet.) */
export function Contacts({ query, head = null, over = null, onWrite, onProfile }) {
  const [rows, setRows] = useState([]);
  const [seen, setSeen] = useState({});   // each person's presence line (iOS: «online», «last seen …» under the name)
  const [exact, setExact] = useState(true);
  const look = () => invoke("chats").then((all) => {
    // people alone (iOS ContactsTabView, mtContacts): a group is no contact, nor Saved Messages, the room of writing to oneself
    const pairs = all.filter((r) => !r.group && r.ref !== SAVED);
    setRows(pairs);
    // answered once every presence is: one word of the book asks for one round of them at a time (Chats.jsx useChanged)
    return Promise.all(pairs.map((r) => invoke("presence", { chat: r.ref }).then((s) => [r.ref, s]).catch(() => [r.ref, null])))
      .then((l) => setSeen(Object.fromEntries(l)));
  });
  useEffect(() => {
    look();
    invoke("settings_get").then((s) => setExact(s.presenceSharing !== false)).catch(() => {});
    const id = setInterval(look, 30000);
    return () => clearInterval(id);
  }, []);
  useChanged(look);
  const q = query.trim().toLowerCase();
  const people = rows.map((r) => ({ ...r, shown: chatName(r.name) }))
    .filter((r) => !q || r.shown.toLowerCase().includes(q))
    .sort((a, b) => a.shown.localeCompare(b.shown, locale));
  // THE SEARCH'S RESULTS OVER THE ROWS (iOS: the same field and the same results on the chats, the contacts and the calls pages)
  if (over) return <div className="rows searching">{head}{over}</div>;
  if (!rows.length) return <>{head}<div className="empty-pane"><div className="empty-text">{t("No contacts yet")}</div></div></>;
  return (
    <div className="rows">
      {/* the search is the list's first row and scrolls with it, as on the chats (iOS MontanaTimePanelList); it stays one field
          while the word narrows the rows to none */}
      {head}
      {!people.length && <div className="no-results">{t("No results")}</div>}
      {people.map((r) => (
        <div key={r.ref} className="row" role="button" tabIndex={0} onClick={() => onWrite(r.ref)}
             aria-label={!r.blocked && seenText(seen[r.ref], exact) ? `${r.shown}, ${seenText(seen[r.ref], exact)[0]}` : r.shown}
             onContextMenu={(e) => { e.preventDefault(); onProfile(r); }} onKeyDown={(e) => e.key === "Enter" && onWrite(r.ref)}>
          <Face chat={r.ref} version={r.face} size={48} live={!r.blocked && !!seenText(seen[r.ref], exact)?.[1]} />
          <div className="words"><div className="top"><span className="name">{r.shown}</span></div>
            {!r.blocked && seenText(seen[r.ref], exact) && (
              <div className="bottom"><span className={"preview" + (seenText(seen[r.ref], exact)[1] ? " live-word" : "")}>{seenText(seen[r.ref], exact)[0]}</span></div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}

/** CALLS (iOS CallsTabView): the log, newest first -- a day's pill before the first call of each day (iOS dayMark: MTDayLabel on
 *  the long octagon, no separator), then the name (red when missed), the direction, the camera, the state, the clock; a tap
 *  calls back the same way. A hold -- here the right button -- opens the menu: select, delete, block; selecting, a tap marks the
 *  row and the bar below carries the cross out, the bin for the chosen and the bin for all, glyphs only. A call leaves the log as
 *  its row leaves the chat, for me alone (iOS deleteCallLog: dropRows). «New Call» in the pages' corner leads to the contacts,
 *  where a person's row dials (iOS mtPageAction, phone.badge.plus). */
export function Calls({ onNewCall, onBlock }) {
  const [rows, setRows] = useState(null);
  const [selecting, setSelecting] = useState(false);
  const [chosen, setChosen] = useState(() => new Set());
  const [menu, setMenu] = useState(null);
  const look = () => invoke("calls_log").then(setRows);
  useEffect(() => { look(); }, []);
  useChanged(look);
  if (!rows) return null;
  const id = (r) => `${r.chat}/${r.mid}`;
  const end = () => { setSelecting(false); setChosen(new Set()); };
  const drop = async (list) => {
    const by = {};
    for (const r of list) (by[r.chat] ||= []).push(r.mid);
    await Promise.all(Object.entries(by).map(([chat, mids]) => invoke("chat_delete", { chat, mids, everyone: false }).catch(() => {})));
    look();
  };
  const toggle = (r) => setChosen((s) => { const n = new Set(s); if (n.has(id(r))) n.delete(id(r)); else n.add(id(r)); return n; });
  const door = !selecting && (
    <button className="compose-door" onClick={onNewCall} aria-label={t("New Call")}><Glyph name="phonePlus" size={24} color="#fff" /></button>
  );
  if (!rows.length) {
    return <><div className="empty-pane"><div className="empty-text pre">{t("Your audio and video calls\nwill appear here")}</div></div>{door}</>;
  }
  const state = (r) => (r.miss ? (r.inc ? t("Missed") : t("No answer")) : r.dur > 0 ? `${Math.floor(r.dur / 60)}:${String(r.dur % 60).padStart(2, "0")}` : t("The connection failed"));
  const deed = (label, glyph, act, red) => (
    <button className={"menu-row" + (red ? " red" : "")} role="menuitem" onClick={() => { setMenu(null); act(); }}><span>{t(label)}</span><Glyph name={glyph} size={18} /></button>
  );
  return (
    <>
    <div className="rows">
      {rows.map((r, i) => (
        <Fragment key={id(r)}>
        {(i === 0 || dayWord(rows[i - 1].at) !== dayWord(r.at)) && <div className="calls-day"><span>{dayWord(r.at)}</span></div>}
        <div className="row" role="button" tabIndex={0} aria-label={`${chatName(r.name)}, ${state(r)}`} aria-pressed={selecting ? chosen.has(id(r)) : undefined}
             onClick={() => (selecting ? toggle(r) : callTo(r.chat, r.name, !!r.v))}
             onContextMenu={(e) => { e.preventDefault(); if (!selecting) setMenu({ r, x: e.clientX, y: e.clientY }); }}>
          {selecting && <Glyph name={chosen.has(id(r)) ? "checkCircle" : "circle"} size={22} color={chosen.has(id(r)) ? "var(--blue)" : "var(--gray)"} />}
          <Face chat={r.chat} version={r.face} size={48} />
          <div className="words">
            <div className="top"><span className="name" style={{ color: r.miss ? "var(--red)" : undefined }}>{chatName(r.name)}</span>
              <span className="time">{new Date(r.at).toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" })}</span></div>
            <div className="bottom">
              <Glyph name={r.inc ? "callIn" : "callOut"} size={12} color={r.miss ? "var(--red)" : "var(--green)"} />
              {r.v && <Glyph name="video" size={11} color="var(--gray)" />}
              <span className="preview">{state(r)}</span>
              <Glyph name={r.v ? "video" : "calls"} size={18} color="#fff" />
            </div>
          </div>
        </div>
        </Fragment>
      ))}
    </div>
    {selecting && (
      <div className="calls-select-bar">
        <button className="calls-bar-button" onClick={end} aria-label={t("Cancel")}><Glyph name="close" size={18} color="#fff" /></button>
        <span className="calls-bar-gap" />
        <button className="calls-bar-button" disabled={!chosen.size} aria-label={t("Delete")}
                onClick={() => { drop(rows.filter((r) => chosen.has(id(r)))); end(); }}><Glyph name="trash" size={18} color="#fff" /></button>
        <button className="calls-bar-button" aria-label={t("Delete All")} onClick={() => { drop(rows); end(); }}><Glyph name="binX" size={18} color="#fff" /></button>
      </div>
    )}
    {door}
    {menu && (
      <div className="menu-shade" onClick={() => setMenu(null)} onContextMenu={(e) => { e.preventDefault(); setMenu(null); }}>
        <div className="letter-menu" style={{ left: Math.min(menu.x, window.innerWidth - 250), top: Math.min(menu.y, window.innerHeight - 170) }}
             onClick={(e) => e.stopPropagation()} role="menu">
          <div className="menu-rows">
            {deed("Select", "checkCircle", () => { setSelecting(true); setChosen(new Set([id(menu.r)])); })}
            {deed("Delete", "trash", () => drop([menu.r]), true)}
            {menu.r.blocked
              ? deed("Unblock", "hand", () => invoke("chat_block", { chat: menu.r.chat, on: false }).then(look))
              : deed("Block", "hand", () => onBlock(menu.r), true)}
          </div>
        </div>
      </div>
    )}
    </>
  );
}

const dayOf = (at) => new Date(at).toLocaleDateString(locale, { day: "numeric", month: "long", year: "numeric" });

function Tile({ f, onOpen }) {
  const url = useFile(f.mid, f.file && f.m.k === "img", f.m.e);
  const th = f.m.th ? `data:image/jpeg;base64,${f.m.th}` : null;
  return (
    <button className="tile" onClick={() => onOpen(f)} aria-label={f.name}>
      {(url || th) && <img src={url || th} alt="" />}
      {f.m.k === "vid" && <span className="tile-video">▶</span>}
    </button>
  );
}

/** GALLERY (iOS GalleryTabView): every picture and film of every conversation, day by day, three to a row; a tap opens it
 *  in its chat. */
export function Gallery({ query, onOpen }) {
  const [files, setFiles] = useState(null);
  const look = () => invoke("media_list").then(setFiles);
  useEffect(() => { look(); }, []);
  useChanged(look);
  const end = useRef(null);
  useEffect(() => { end.current?.scrollIntoView(); }, [files?.length]);
  if (!files) return null;
  const q = query.trim().toLowerCase();
  const shown = files.filter((f) => (f.m.k === "img" || f.m.k === "vid") && (!q || chatName(f.name).toLowerCase().includes(q)));
  if (!shown.length) return <div className="empty-pane"><div className="empty-text">{q ? t("No results") : t("No photos yet")}</div></div>;
  const days = [];
  for (const f of shown) {
    const d = dayOf(f.at);
    if (!days.length || days[days.length - 1][0] !== d) days.push([d, []]);
    days[days.length - 1][1].push(f);
  }
  return (
    <div className="gallery">
      {days.map(([d, fs]) => (
        <div key={d}>
          <div className="gallery-day">{d}</div>
          <div className="gallery-grid">{fs.map((f) => <Tile key={f.mid} f={f} onOpen={(x) => onOpen(x.chat)} />)}</div>
        </div>
      ))}
      <div ref={end} />
    </div>
  );
}

/** A row of the music page (iOS MTTrackRow.face): the tag's name and the length, read when the row stands (MTTrackMeta.load). */
function MusicRow({ x, playing, paused, onTap }) {
  const box = useRef(null);
  const [seen, setSeen] = useState(false);
  useEffect(() => {
    const el = box.current;
    if (!el || seen || typeof IntersectionObserver === "undefined") return undefined;
    const io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) { setSeen(true); io.disconnect(); } });
    io.observe(el);
    return () => io.disconnect();
  }, [seen]);
  const m = player.useMeta(seen ? x : null);
  return (
    <div data-file={x.file} ref={box}>
      <TrackRow title={m?.title || x.title} length={m?.length || 0} playing={playing} paused={paused} onTap={onTap} />
    </div>
  );
}

/** MUSIC (iOS MusicTabView): every track a row in the mini's form, newest first -- the track that plays wears the thin blue ring,
 *  and the one floating player stands at the page's foot; a tap plays the track with the list as the queue, a tap on the playing
 *  one rests it or plays it on. The page's own search narrows the list by the track's name and where it lies. The plus at the bottom
 *  right (the chats' compose door one to one) lends a folder: Windows' own folder picker, its music read where it lies -- never
 *  copied into a chat; it turns while the folder is walked. Where the music plays from is the big player's filter. */
export function Music({ query }) {
  const [files, setFiles] = useState(null);
  const [lent, setLent] = useState({ folders: [], tracks: [] });
  const [walking, setWalking] = useState(false);
  const now = player.usePlayer();
  const box = useRef(null);
  const look = () => invoke("media_list").then(setFiles);
  const lookLent = () => invoke("music_state").then(setLent).catch(() => {});
  useEffect(() => { look(); lookLent(); }, []);
  useChanged(look);
  // THE TRACK'S PLACE ASKED (iOS MTMusicFocus): its row comes to the middle of the page
  const place = (file) => {
    const el = file && box.current?.querySelector(`[data-file="${CSS.escape(file)}"]`);
    if (el) { el.scrollIntoView({ block: "center", behavior: "smooth" }); el.classList.add("flash"); setTimeout(() => el.classList.remove("flash"), 900); }
  };
  useEffect(() => {
    const on = (e) => place(e.detail);
    window.addEventListener("montana-music-place", on);
    return () => window.removeEventListener("montana-music-place", on);
  }, []);
  useEffect(() => { if (files) { const f = player.takePlace(); if (f) setTimeout(() => place(f), 50); } }, [files]);
  if (!files) return null;
  const q = query.trim().toLowerCase();
  const all = player.library(files, lent.tracks).reverse()
    .filter((x) => !q || [player.nameOf(x), x.title, player.metaOf(x)?.artist || "", x.chatTitle || ""].some((w) => w.toLowerCase().includes(q)));
  const lend = async () => {
    if (walking) return;
    setWalking(true);
    const ok = await invoke("music_folder_add").catch(() => false);
    setWalking(false);
    invoke("trace", { line: `music_lent pick ${ok ? "lent" : "refused"}` }).catch(() => {});
    if (ok) lookLent();
  };
  const tap = (x, i) => {
    if (!now.voice && now.file === x.file) {
      invoke("trace", { line: `music_tab tap ${now.paused ? "on" : "rest"}` }).catch(() => {});
      return player.toggle();
    }
    invoke("trace", { line: `music_tab tap play i=${i + 1} n=${all.length}` }).catch(() => {});
    player.playQueue(all, i);
  };
  return (
    <>
      {all.length ? (
        <div className="rows tracks mini" ref={box}>
          {all.map((x, i) => (
            <MusicRow key={x.file} x={x} playing={!now.voice && now.file === x.file} paused={now.paused} onTap={() => tap(x, i)} />
          ))}
        </div>
      ) : <div className="empty-pane"><div className="empty-text">{q ? t("Nothing found") : t("Your music will appear here")}</div></div>}
      <button className="compose-door" onClick={lend} aria-label={t("Add a folder")}>
        {walking ? <span className="spinner" /> : <Glyph name="plus" size={26} color="var(--bar-glyph)" />}
      </button>
    </>
  );
}
