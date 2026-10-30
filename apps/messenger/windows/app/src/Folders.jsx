import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { BOT, BOT_ROW, BotFace, Face, SAVED, SelfFace, Swipe, rowTitle } from "./Chats.jsx";
import { Page, SHEET_GROUND, Section } from "./Settings.jsx";

/** THE FOLDERS OVER THE CHATS (iOS MTChatFolders): All and the person's folders, each the kinds of chats and the chats it takes,
 *  the states and the chats it leaves out; kept in the vault in iOS's own shape («chatFolders»). Our bot's row lives in All and in
 *  the Bots folder, as iOS keeps it (MTBot). */
export const ALL = "all";
const ALL_FOLDER = { id: ALL, title: "", kinds: [], chats: [], leaves: [], excluded: [] };
const PERSONAL = ["contacts", "nonContacts"];
/** The first tabs (iOS firstFolders): All, the chats, the groups, the channels, the bots. */
const FIRST = [
  ALL_FOLDER,
  { id: "chats", title: "", preset: "contacts", kinds: PERSONAL, chats: [], leaves: ["archived"], excluded: [] },
  { id: "groups", title: "", preset: "groups", kinds: ["groups"], chats: [], leaves: ["archived"], excluded: [] },
  { id: "channels", title: "", preset: "channels", kinds: ["channels"], chats: [], leaves: ["archived"], excluded: [] },
  { id: "bots", title: "", preset: "bots", kinds: ["bots"], chats: [], leaves: ["archived"], excluded: [] },
];
const EVENT = "montana-folders";

export async function loadFolders() {
  const raw = await invoke("folders_get").catch(() => "");
  try {
    const kept = JSON.parse(raw || "[]");
    if (Array.isArray(kept) && kept.some((f) => f.id === ALL)) return kept.map((f) => ({ title: "", kinds: [], chats: [], leaves: [], excluded: [], ...f }));
  } catch { /* the first folders, as iOS falls back */ }
  return FIRST;
}

async function saveFolders(folders) {
  await invoke("folders_set", { folders: JSON.stringify(folders) });
  window.dispatchEvent(new Event(EVENT));
}

/** The folders, read again whenever they change. */
export function useFolders() {
  const [folders, setFolders] = useState(FIRST);
  useEffect(() => {
    const look = () => loadFolders().then(setFolders);
    look();
    window.addEventListener(EVENT, look);
    return () => window.removeEventListener(EVENT, look);
  }, []);
  return folders;
}

/** A folder's name in the person's language while it keeps the name of its kind (iOS shownTitle). */
export function folderTitle(f) {
  if (f.id === ALL) return t("All");
  if (f.title || !f.preset) return f.title;
  return { contacts: t("Chats"), nonContacts: t("Chats"), groups: t("Groups"), channels: t("Channels"), bots: t("Bots") }[f.preset] || f.title;
}

/** What a conversation is to the folders (iOS MTChatFolders.kind): our bot, a channel, a group; a person is a contact when the
 *  address book holds their card -- Windows holds no book (iOS mtContacts), so every person stands as iOS stands them on a phone
 *  with an empty book: a non-contact. */
const kindsOf = (r) => (r.ref === BOT ? ["bots"] : r.kind === "c" ? ["channels"] : r.kind === "g" || r.group ? ["groups"] : ["nonContacts"]);
const unreadOf = (r) => r.unread > 0 || r.marked;

/** Whether a conversation stands in the folder (iOS takes): taken by its kind or by name, not left out by name or by a state. */
export function takes(f, r) {
  if (f.id === ALL) return !r.archived;
  if ((f.excluded || []).includes(r.ref)) return false;
  if (!kindsOf(r).some((k) => f.kinds.includes(k)) && !(f.chats || []).includes(r.ref)) return false;
  if (r.muted && f.leaves.includes("muted")) return false;
  if (!unreadOf(r) && f.leaves.includes("read")) return false;
  if (r.archived && f.leaves.includes("archived")) return false;
  return true;
}

/** A tab's badge (iOS badge): the folder's unread conversations, blue while one of them is not muted; All wears none. */
function badge(f, rows) {
  if (f.id === ALL) return { count: 0, loud: false };
  const mine = rows.filter((r) => !r.blocked && takes(f, r) && unreadOf(r));
  return { count: mine.length, loud: mine.some((r) => !r.muted) };
}

/** SF arrow.left.arrow.right (the menu's «Reorder Tabs»), drawn at its shape. */
function ArrowsLeftRight({ size = 18 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <path d="M4 8h15M15 4l4 4-4 4M20 16H5M9 12l-4 4 4 4" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** THE FOLDERS' TABS (iOS MTFolderTabs): one glass capsule the list's width at the time panel's side margins -- the panel's own
 *  plate, 60 high and 14 within its sides --, the names from its left edge 4 in, 6 apart, each 10 within and 44 at least, the
 *  chosen one on the panel's own puck (36 high), which slides to the next name in 0.25 s. A hold -- here the right button, or a
 *  long touch -- opens the folder's menu (iOS contextMenu): its page, its chats, read all, mute all, remove; on All the folders'
 *  page; with more than one folder, the order of the tabs. */
export function FolderTabs({ folders, rows, chosen, onPick, onOpen }) {
  const strip = useRef(null);
  const [puck, setPuck] = useState(null);
  const [menu, setMenu] = useState(null);         // {f, x, y}
  const [removing, setRemoving] = useState(null);
  useLayoutEffect(() => {
    const b = strip.current?.querySelector(".folder-tab.on");
    if (!b) { setPuck(null); return; }
    setPuck({ left: b.offsetLeft, width: b.offsetWidth });
    b.scrollIntoView({ block: "nearest", inline: "center", behavior: puck ? "smooth" : "auto" });
  }, [chosen, folders.length]);
  // THE STRIP SCROLLS SIDEWAYS UNDER THE WHEEL (iOS: the finger's sideways stroke on an overflowing strip): a mouse's wheel turned
  // over the names moves them along, the touchpad's sideways stroke as it always did
  useEffect(() => {
    const el = strip.current;
    if (!el) return undefined;
    const wheel = (e) => {
      if (el.scrollWidth <= el.clientWidth + 1 || Math.abs(e.deltaX) > Math.abs(e.deltaY)) return;
      e.preventDefault();
      el.scrollLeft += e.deltaY * (e.deltaMode === 1 ? 33 : 1);
    };
    el.addEventListener("wheel", wheel, { passive: false });
    return () => el.removeEventListener("wheel", wheel);
  }, []);
  const inside = (f) => rows.filter((r) => !r.blocked && takes(f, r));
  const item = (label, glyph, act, red) => (
    <button className={"menu-row" + (red ? " red" : "")} role="menuitem" onClick={() => { setMenu(null); act(); }}>
      <span>{label}</span>{typeof glyph === "string" ? <Glyph name={glyph} size={18} /> : glyph}
    </button>
  );
  const folderMenu = (f) => {
    if (f.id === ALL) return item(t("Edit Folders"), "pencil", () => onOpen({}));
    const mine = inside(f);
    const allMuted = mine.length > 0 && mine.every((r) => r.muted);
    return (<>
      {item(t("Edit Folder"), "pencil", () => onOpen({ edit: f.id }))}
      {item(t("Add Chats"), "plus", () => onOpen({ add: f.id }))}
      {mine.some(unreadOf) && item(t("Read All"), "markRead", () => mine.filter(unreadOf).forEach((r) => invoke("chat_flag", { chat: r.ref, flag: "unread", on: false })))}
      {mine.length > 0 && (allMuted
        ? item(t("Unmute All"), "bellFill", () => mine.forEach((r) => invoke("chat_flag", { chat: r.ref, flag: "mute", on: false })))
        : item(t("Mute All"), "bellSlash", () => mine.filter((r) => !r.muted).forEach((r) => invoke("chat_flag", { chat: r.ref, flag: "mute", on: true }))))}
      {item(t("Remove"), "trash", () => setRemoving(f), true)}
    </>);
  };
  return (
    <div className="folder-tabs" role="group" aria-label={t("Folders")} ref={strip}>
      {puck && <span className="folder-puck" style={{ transform: `translateX(${puck.left}px)`, width: puck.width }} aria-hidden="true" />}
      {folders.map((f) => {
        const b = badge(f, rows);
        const on = f.id === chosen;
        return (
          <button key={f.id} aria-pressed={on} aria-label={`${t("Folder")}: ${folderTitle(f)}${b.count ? ` (${b.count})` : ""}`}
                  className={"folder-tab" + (on ? " on" : "")} onClick={() => onPick(f.id)}
                  onContextMenu={(e) => { e.preventDefault(); setMenu({ f, x: e.clientX, y: e.clientY }); }}>
            <span>{folderTitle(f)}</span>
            {b.count > 0 && <span className={"folder-count" + (b.loud || on ? " loud" : "")}>{b.count}</span>}
          </button>
        );
      })}
      {menu && (
        <div className="menu-shade" onClick={() => setMenu(null)} onContextMenu={(e) => { e.preventDefault(); setMenu(null); }}>
          <div className="letter-menu" style={{ left: Math.min(menu.x, window.innerWidth - 270), top: Math.min(menu.y, window.innerHeight - 330) }}
               onClick={(e) => e.stopPropagation()} role="menu" aria-label={folderTitle(menu.f)}>
            <div className="menu-rows">
              {folderMenu(menu.f)}
              {folders.length > 1 && <div className="menu-divider" role="separator" />}
              {folders.length > 1 && item(t("Reorder Tabs"), <ArrowsLeftRight />, () => onOpen({ reorder: true }))}
            </div>
          </div>
        </div>
      )}
      {removing && (
        <div className="alert-shade" onClick={() => setRemoving(null)}>
          <div className="alert" role="alertdialog" onClick={(e) => e.stopPropagation()}>
            <div className="alert-title">{t("Remove %@?").replace("%@", folderTitle(removing))}</div>
            <div className="alert-text">{t("This will remove the folder, your chats will not be deleted.")}</div>
            <div className="alert-keys stacked">
              <button className="red" onClick={() => {
                const f = removing;
                setRemoving(null);
                saveFolders(folders.filter((x) => x.id !== f.id));
                if (f.id === chosen) onPick(ALL);   // the chosen folder removed falls back to All
              }}>{t("Remove")}</button>
              <button className="bold" onClick={() => setRemoving(null)}>{t("Cancel")}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/** A FOLDER WITH NO CHATS (iOS MontanaChatsList: the folder glyph, «Folder is empty.», what it means). */
export function FolderEmpty() {
  return (
    <div className="folder-empty">
      <FolderGlyph size={44} color="var(--gray)" />
      <b>{t("Folder is empty.")}</b>
      <span>{t("No chats currently match this folder.")}</span>
    </div>
  );
}

/** SF folder.fill, drawn at its shape (the folders' page intro and the empty folder). */
function FolderGlyph({ size = 64, color = "#fff" }) {
  return (
    <svg width={size} height={size * 0.8} viewBox="0 0 30 24" aria-hidden="true">
      <path d="M2 5.5C2 3.6 3.6 2 5.5 2h6.2c.9 0 1.7.4 2.3 1l1.6 1.8c.4.5 1 .7 1.6.7h7.3c1.9 0 3.5 1.6 3.5 3.5v11.5c0 1.9-1.6 3.5-3.5 3.5h-19C3.6 24 2 22.4 2 20.5z"
            fill={color} />
    </svg>
  );
}

const fresh = () => ({ id: crypto.randomUUID(), title: "", kinds: [], chats: [], leaves: ["archived"], excluded: [] });
const alike = (a, b) => [...a.kinds].sort().join() === [...b.kinds].sort().join() && [...a.leaves].sort().join() === [...b.leaves].sort().join()
  && !a.chats.length && !b.chats.length && !a.excluded.length && !b.excluded.length;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/** THE KINDS AND THE STATES (iOS MTChatFolder.Kind / Leave): the word and the tint of its circle -- the platform's dark colours (blue, teal,
 *  green, indigo, purple; red, blue, grey). */
const KINDS = [["contacts", "Contacts", "#0a84ff"], ["nonContacts", "Non-Contacts", "#40c8e0"], ["groups", "Groups", "#30d158"],
  ["channels", "Channels", "#5e5ce6"], ["bots", "Bots", "#bf5af2"]];
const LEAVES = [["muted", "Muted", "#ff453a"], ["read", "Read", "#0a84ff"], ["archived", "Archived", "#8e8e93"]];

/** The glyph of a kind or a state (SF person.crop.circle, person.crop.circle.badge.questionmark, person.2, megaphone, cpu;
 *  bell.slash, checkmark.message, archivebox): the Windows set's own where it has one, drawn at the symbol's shape where not. */
function KindGlyph({ k, size }) {
  const own = { contacts: "contacts", groups: "people", muted: "bellSlash", read: "markRead", archived: "archive" }[k];
  if (own) return <Glyph name={own} size={size} color="#fff" />;
  const box = (paths) => <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" style={{ display: "block" }}>{paths}</svg>;
  if (k === "nonContacts") {
    return box(<>
      <circle cx="11" cy="12" r="8.6" fill="none" stroke="#fff" strokeWidth="1.8" />
      <circle cx="11" cy="9.6" r="2.9" fill="none" stroke="#fff" strokeWidth="1.8" />
      <path d="M5.8 17.6c1.3-2 3-3 5.2-3s3.9 1 5.2 3" fill="none" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" />
      <circle cx="18.6" cy="17.6" r="4.6" fill="#fff" />
      <path d="M17.2 16.4a1.5 1.5 0 1 1 2 1.4c-.5.2-.6.5-.6.9" fill="none" stroke="#000" strokeWidth="1.3" strokeLinecap="round" />
      <circle cx="18.6" cy="20.1" r=".75" fill="#000" />
    </>);
  }
  if (k === "channels") {
    return box(<>
      <path d="M3.5 10.2v3.6c0 .7.5 1.2 1.2 1.2h2.1l5.7 3.9c.6.4 1.4 0 1.4-.7V5.8c0-.7-.8-1.1-1.4-.7L6.8 9H4.7c-.7 0-1.2.5-1.2 1.2z" fill="none" stroke="#fff" strokeWidth="1.8" strokeLinejoin="round" />
      <path d="M17.3 9a4.2 4.2 0 0 1 0 6M7.4 15.4l1 4.1c.2.7.8 1 1.4.8" fill="none" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" />
    </>);
  }
  return box(<>
    <rect x="6.5" y="6.5" width="11" height="11" rx="2.2" fill="none" stroke="#fff" strokeWidth="1.8" />
    <rect x="9.6" y="9.6" width="4.8" height="4.8" rx=".8" fill="#fff" />
    <path d="M9.5 3.5v3M14.5 3.5v3M9.5 17.5v3M14.5 17.5v3M3.5 9.5h3M3.5 14.5h3M17.5 9.5h3M17.5 14.5h3" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" />
  </>);
}
const kindOf = (k) => [...KINDS, ...LEAVES].find((x) => x[0] === k) || [k, k, "#8e8e93"];
/** A kind's or a state's circle in its tint (iOS kindLine 32 with the glyph 15, typeLine 40 with the glyph 17). */
const KindCircle = ({ k, side }) => (
  <span className="kind-circle" style={{ width: side, height: side, background: kindOf(k)[2] }}><KindGlyph k={k} size={side === 40 ? 21 : 18} /></span>
);
/** SF plus.circle.fill / minus.circle.fill: white on the platform's blue. */
const CircleMark = ({ minus, size = 22 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" style={{ display: "block" }}>
    <circle cx="12" cy="12" r="11" fill="var(--blue)" />
    <path d={minus ? "M7 12h10" : "M7 12h10M12 7v10"} stroke="#fff" strokeWidth="2.2" strokeLinecap="round" />
  </svg>
);
/** SF checkmark.circle.fill (white) / circle (secondary), the pickers' tick at title3. */
const Tick = ({ on }) => (on
  ? <svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="#fff" /><path d="M7 12.4l3.2 3.2L17 8.8" fill="none" stroke="#000" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" /></svg>
  : <svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10.2" fill="none" stroke="var(--gray)" strokeWidth="1.6" /></svg>);
/** The face of a conversation a folder names: our bot's glass icon, my own face for Saved Messages, else theirs. */
const PoolFace = ({ r, side, me }) => (r.ref === BOT ? <BotFace size={side} /> : r.ref === SAVED ? <SelfFace name={me?.name} version={me?.face} size={side} />
  : <Face chat={r.ref} version={r.face} size={side} />);

/** A LINE THAT GOES BY THE PLATFORM'S SWIPE (iOS List .onDelete): drawn to the left it uncovers the red «Delete». */
function Deletable({ label, onDelete, children }) {
  const [side, setSide] = useState(0);
  return (
    <Swipe free trailing={[{ text: t("Delete"), label: `${t("Delete")}: ${label}`, act: onDelete, red: true }]} side={side} onSide={setSide}>
      {children}
    </Swipe>
  );
}

/** THE FOLDERS' PAGE (iOS MTFolderSettingsPage, MTChatFolders.swift 305-464): what folders are for -- folder.fill 64 and its words;
 *  «Create a Folder»; the folders with the count of their chats and the chevron, All among them and never taken away; under them
 *  «Tap the pencil to change the order or delete folders.»; the pencil turns the list to its editing -- the red minus and the
 *  handle on each folder but All, the checkmark ends it -- and the folders the reference recommends, each with its plus. Over the
 *  tabs (a tab's menu: iOS overlayPage .folders, ContentView.swift 2486) its mark is the cross, and it rides in from the trailing edge
 *  in 0.25 s and goes at once, as the app's slot shows its pages; from Settings it is pushed, its mark the way back. */
export function FoldersPage({ onClose, opening = {}, pushed = false, me: given }) {
  const folders = useFolders();
  const [me, setMe] = useState(given);   // my own face for Saved Messages in the pickers
  useEffect(() => { if (!given) invoke("identity_state").then(setMe).catch(() => {}); }, []);
  const [rows, setRows] = useState([]);
  const [editor, setEditor] = useState(null);       // {folder, add}
  const [editing, setEditing] = useState(!!opening.reorder);
  const [doomed, setDoomed] = useState(null);       // the folder whose minus was tapped: its «Delete» stands at its end
  const [order, setOrder] = useState(null);         // the order under the handle while a folder is carried
  // THE POOL (iOS MTFolderChatPicker.pool): the list's own rows -- not the archived, which the list does not hold -- and our bot
  useEffect(() => { invoke("chats").then((r) => setRows([...r.filter((x) => !x.archived), BOT_ROW])).catch(() => {}); }, []);
  // THE MENU'S WAY IN (iOS MTChatFolders.opening): a folder's page, or its chats to pick, once the folders are read
  const opened = useRef(false);
  useEffect(() => {
    const id = opening.edit || opening.add;
    if (opened.current || !id) return;
    loadFolders().then((all) => {
      const f = all.find((x) => x.id === id);
      if (!f || opened.current) return;
      opened.current = true;
      setEditor({ folder: f, add: !!opening.add });
    });
  }, []);
  const put = (list) => saveFolders(list);
  const shownFolders = order || folders;
  const offered = [
    { id: "unread", title: t("Unread"), words: t("New messages from all chats."), f: { kinds: KINDS.map((k) => k[0]), leaves: ["read", "archived"] } },
    { id: "personal", title: t("Personal"), words: t("Only messages from personal chats."), f: { kinds: PERSONAL, leaves: ["archived"] } },
    { id: "groups", title: t("Groups"), words: t("Only messages from groups."), f: { preset: "groups", kinds: ["groups"], leaves: ["archived"] } },
    { id: "channels", title: t("Channels"), words: t("Only messages from channels."), f: { preset: "channels", kinds: ["channels"], leaves: ["archived"] } },
    { id: "bots", title: t("Bots"), words: t("Only messages from bots."), f: { preset: "bots", kinds: ["bots"], leaves: ["archived"] } },
  ].map((s) => ({ ...s, f: { ...fresh(), ...s.f } })).filter((s) => !folders.some((f) => alike(f, s.f)));
  // THE HANDLE (iOS .onMove): the folder follows the pointer up or down by whole lines, the rest make room; let go, the order is kept
  const carry = (e, i) => {
    e.preventDefault();
    const line = e.currentTarget.closest(".set-row");
    const h = line?.offsetHeight || 44;
    const y0 = e.clientY;
    let at = i, list = [...folders];
    const move = (m) => {
      const to = Math.max(0, Math.min(list.length - 1, i + Math.round((m.clientY - y0) / h)));
      if (to === at) return;
      const l = [...folders];
      const [f] = l.splice(i, 1);
      l.splice(to, 0, f);
      at = to; list = l;
      setOrder(l);
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      if (at !== i) put(list);
      setTimeout(() => setOrder(null), 50);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  if (editor) {
    return <FolderEdit folder={editor.folder} rows={rows} me={me} isNew={!folders.some((f) => f.id === editor.folder.id)} adding={editor.add}
                       onClose={() => setEditor(null)}
                       onKeep={(f) => { put(folders.some((x) => x.id === f.id) ? folders.map((x) => (x.id === f.id ? f : x)) : [...folders, f]); setEditor(null); }} />;
  }
  const mark = editing
    ? <button className="glass-mark" onClick={() => { setEditing(false); setDoomed(null); }} aria-label={t("Done")}><Glyph name="tick" size={18} color="var(--bar-glyph)" /></button>
    : <button className="glass-mark" onClick={() => setEditing(true)} aria-label={t("Edit")}><Glyph name="pencil" size={18} color="var(--bar-glyph)" /></button>;
  return (
    <Page title={t("Folders")} onClose={onClose} back={pushed} right={mark} motion={pushed ? undefined : "slot"}>
      <div className="folders-intro"><FolderGlyph size={64} color="#fff" />
        <span>{t("Create folders for different groups of chats and quickly switch between them.")}</span></div>
      <Section head={t("Folders")} foot={t("Tap the pencil to change the order or delete folders.")}>
        <button className="set-row" onClick={() => setEditor({ folder: fresh(), add: false })}>
          <span className="row-title" style={{ color: "var(--blue)" }}>{t("Create a Folder")}</span>
        </button>
        {shownFolders.map((f, i) => {
          const count = f.id === ALL ? 0 : rows.filter((r) => takes(f, r)).length;
          if (editing) {
            return (
              <div key={f.id} className="set-row folder-line">
                {f.id !== ALL
                  ? <button className="minus-mark" aria-label={`${t("Delete")}: ${folderTitle(f)}`} onClick={() => setDoomed(doomed === f.id ? null : f.id)}><MinusRed /></button>
                  : <span className="minus-room" />}
                <span className="row-title">{folderTitle(f)}</span>
                {doomed === f.id
                  ? <button className="delete-key" onClick={() => { setDoomed(null); put(folders.filter((x) => x.id !== f.id)); }}>{t("Delete")}</button>
                  : <span className="move-handle" role="button" aria-label={`${t("Reorder")}: ${folderTitle(f)}`} onPointerDown={(e) => carry(e, i)}
                          tabIndex={0} onKeyDown={(e) => {
                            const d = e.key === "ArrowUp" ? -1 : e.key === "ArrowDown" ? 1 : 0;
                            if (!d || !folders[i + d]) return;
                            e.preventDefault();
                            const l = [...folders]; [l[i], l[i + d]] = [l[i + d], l[i]]; put(l);
                          }}><Handle /></span>}
              </div>
            );
          }
          return (
            <button key={f.id} className="set-row folder-line" onClick={() => f.id !== ALL && setEditor({ folder: f, add: false })} aria-label={folderTitle(f)}>
              <span className="row-title">{folderTitle(f)}</span>
              {count > 0 && <span className="row-value">{count}</span>}
              {f.id !== ALL && <span className="row-chevron"><Glyph name="chevronRight" size={13} color="rgba(235, 235, 245, 0.3)" /></span>}
            </button>
          );
        })}
      </Section>
      {offered.length > 0 && (
        <Section head={t("Recommended Folders")}>
          {offered.map((s) => (
            <button key={s.id} className="set-row" aria-label={s.title}
                    onClick={() => put([...folders, { ...s.f, title: s.f.preset ? "" : s.title }])}>
              <span className="row-title"><span>{s.title}</span><span className="row-caption footnote">{s.words}</span></span>
              <CircleMark size={24} />
            </button>
          ))}
        </Section>
      )}
    </Page>
  );
}
/** The edit's red minus (SF minus.circle.fill in the platform's red) and the reorder handle (line.3.horizontal). */
const MinusRed = () => (
  <svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="var(--red)" /><path d="M7 12h10" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" /></svg>
);
const Handle = () => (
  <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16" stroke="var(--gray)" strokeWidth="1.8" strokeLinecap="round" /></svg>
);

/** A FOLDER'S PAGE (iOS MTFolderEditPage, MTChatFolders.swift 469-598): its name; the chats it takes -- «Add Chats», the kinds in their
 *  tinted circles, the conversations with their faces -- and the chats it leaves out -- «Add Chats to Exclude», the states, the
 *  conversations; each line goes by the swipe. The checkmark keeps it once it has a name and takes something (at 0.4 before); the
 *  cross leaves it, asking first when something was changed («You have changed the filter. Discard changes?»). */
function FolderEdit({ folder, rows, me, isNew, adding, onClose, onKeep }) {
  const [draft, setDraft] = useState(folder);
  const startName = isNew ? "" : folderTitle(folder);
  const [name, setName] = useState(startName);
  const [picking, setPicking] = useState(adding ? "in" : null);   // "in" | "out"
  const [asking, setAsking] = useState(false);
  const typed = name.trim();
  const canKeep = !!typed && (draft.kinds.length > 0 || draft.chats.length > 0);
  const changed = !same(draft, folder) || typed !== startName;
  const keep = () => {
    if (!canKeep) return;
    const f = { ...draft };
    if (!isNew && !folder.title && typed === folderTitle(folder)) f.title = "";   // a first folder keeps following the language
    else { f.title = typed; delete f.preset; }
    onKeep(f);
  };
  const lineOf = (ref) => rows.find((r) => r.ref === ref) || { ref, name: ref.slice(0, 10) };
  if (picking) return <FolderPicker taking={picking === "in"} folder={draft} rows={rows} me={me} onDone={(f) => { setDraft(f); setPicking(null); }} />;
  const chatLine = (ref, drop) => {
    const r = lineOf(ref);
    return (
      <Deletable key={ref} label={rowTitle(r.ref, r.name)} onDelete={drop}>
        <div className="set-row"><PoolFace r={r} side={32} me={me} /><span className="row-title one-line">{rowTitle(r.ref, r.name)}</span></div>
      </Deletable>
    );
  };
  const kindLine = (k, drop) => (
    <Deletable key={k} label={t(kindOf(k)[1])} onDelete={drop}>
      <div className="set-row"><KindCircle k={k} side={32} /><span className="row-title">{t(kindOf(k)[1])}</span></div>
    </Deletable>
  );
  return (
    <>
    <Page title={isNew ? t("New Folder") : t("Edit Folder")} onClose={onClose} guard={() => { if (!changed) return true; setAsking(true); return false; }}
          right={<button className="glass-mark" disabled={!canKeep} style={{ opacity: canKeep ? 1 : 0.4 }} onClick={keep} aria-label={t("Done")}>
            <Glyph name="tick" size={18} color="var(--bar-glyph)" /></button>}>
      <Section head={t("Folder Name")}>
        <input className="set-field" placeholder={t("Folder Name")} value={name} maxLength={12 * 4} aria-label={t("Folder Name")} onChange={(e) => setName(e.target.value)} />
      </Section>
      <Section head={t("Included Chats")} foot={t("Choose chats and types of chats that will appear in this folder.")}>
        <button className="set-row" onClick={() => setPicking("in")} aria-label={t("Add Chats")}>
          <span className="mark-room"><CircleMark /></span><span className="row-title" style={{ color: "var(--blue)" }}>{t("Add Chats")}</span>
        </button>
        {draft.kinds.map((k) => kindLine(k, () => setDraft((d) => ({ ...d, kinds: d.kinds.filter((x) => x !== k) }))))}
        {draft.chats.map((c) => chatLine(c, () => setDraft((d) => ({ ...d, chats: d.chats.filter((x) => x !== c) }))))}
      </Section>
      <Section head={t("Excluded Chats")} foot={t("Choose chats and types of chats that will never appear in this folder.")}>
        <button className="set-row" onClick={() => setPicking("out")} aria-label={t("Add Chats to Exclude")}>
          <span className="mark-room"><CircleMark minus /></span><span className="row-title" style={{ color: "var(--blue)" }}>{t("Add Chats to Exclude")}</span>
        </button>
        {draft.leaves.map((k) => kindLine(k, () => setDraft((d) => ({ ...d, leaves: d.leaves.filter((x) => x !== k) }))))}
        {draft.excluded.map((c) => chatLine(c, () => setDraft((d) => ({ ...d, excluded: d.excluded.filter((x) => x !== c) }))))}
      </Section>
    </Page>
    {asking && (
      <div className="alert-shade" onClick={() => setAsking(false)}>
        <div className="alert" role="alertdialog" onClick={(e) => e.stopPropagation()}>
          <div className="alert-title">{t("You have changed the filter. Discard changes?")}</div>
          <div className="alert-keys stacked">
            <button className="red" onClick={() => { setAsking(false); onClose(); }}>{t("Discard")}</button>
            <button className="bold" onClick={() => setAsking(false)}>{t("Cancel")}</button>
          </div>
        </div>
      </div>
    )}
    </>
  );
}

/** THE CHATS OF A FOLDER, CHOSEN (iOS MTFolderChatPicker, MTChatFolders.swift 602-710): a sheet with its search always standing;
 *  without a word the kinds first -- or the states, for the chats left out -- each a circle 40 in its tint and the tick; then every
 *  conversation of the list and our bot, the face 40 and the tick; a chat taken in is not left out, and the other way round; every
 *  tap holds at once, the checkmark returns to the folder. */
function FolderPicker({ taking, folder, rows, me, onDone }) {
  const [f, setF] = useState(folder);
  const [q, setQ] = useState("");
  const flipKind = (k) => setF((x) => ({ ...x, kinds: x.kinds.includes(k) ? x.kinds.filter((y) => y !== k) : [...x.kinds, k] }));
  const flipLeave = (k) => setF((x) => ({ ...x, leaves: x.leaves.includes(k) ? x.leaves.filter((y) => y !== k) : [...x.leaves, k] }));
  const flipChat = (ref) => setF((x) => (taking
    ? { ...x, excluded: x.excluded.filter((y) => y !== ref), chats: x.chats.includes(ref) ? x.chats.filter((y) => y !== ref) : [...x.chats, ref] }
    : { ...x, chats: x.chats.filter((y) => y !== ref), excluded: x.excluded.includes(ref) ? x.excluded.filter((y) => y !== ref) : [...x.excluded, ref] }));
  const word = q.trim().toLowerCase();
  const shown = rows.filter((r) => !word || rowTitle(r.ref, r.name).toLowerCase().includes(word));
  return (
    <Page title={taking ? t("Include Chats") : t("Exclude Chats")} onClose={() => onDone(f)} ground={SHEET_GROUND}
          right={<button className="glass-mark" onClick={() => onDone(f)} aria-label={t("Done")}><Glyph name="tick" size={18} color="var(--bar-glyph)" /></button>}>
      <input className="meet-field pick-search" placeholder={t("Search")} value={q} onChange={(e) => setQ(e.target.value)} aria-label={t("Search")} />
      {!word && (
        <Section head={t("Chat Types")}>
          {(taking ? KINDS : LEAVES).map(([k, w]) => {
            const on = taking ? f.kinds.includes(k) : f.leaves.includes(k);
            return (
              <button key={k} className="set-row" aria-pressed={on} aria-label={t(w)} onClick={() => (taking ? flipKind(k) : flipLeave(k))}>
                <KindCircle k={k} side={40} /><span className="row-title">{t(w)}</span><Tick on={on} />
              </button>
            );
          })}
        </Section>
      )}
      <Section head={t("Chats")}>
        {shown.map((r) => {
          const on = taking ? f.chats.includes(r.ref) : f.excluded.includes(r.ref);
          return (
            <button key={r.ref} className="set-row" aria-pressed={on} aria-label={rowTitle(r.ref, r.name)} onClick={() => flipChat(r.ref)}>
              <PoolFace r={r} side={40} me={me} /><span className="row-title one-line">{rowTitle(r.ref, r.name)}</span><Tick on={on} />
            </button>
          );
        })}
      </Section>
    </Page>
  );
}
