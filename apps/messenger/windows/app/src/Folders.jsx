import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { Face, SAVED, SelfFace, rowTitle } from "./Chats.jsx";
import { Page, Section } from "./Settings.jsx";

/** THE FOLDERS OVER THE CHATS (iOS MTChatFolders): All and the person's folders, each the kinds of chats and the chats it takes,
 *  the states and the chats it leaves out; kept in the vault in iOS's own shape («chatFolders»). Our bot's folder is not here:
 *  the bot is the door to the wallet, which Windows does not open. */
export const ALL = "all";
const ALL_FOLDER = { id: ALL, title: "", kinds: [], chats: [], leaves: [], excluded: [] };
const PERSONAL = ["contacts", "nonContacts"];
/** The first tabs (iOS firstFolders): All, the chats, the groups, the channels. */
const FIRST = [
  ALL_FOLDER,
  { id: "chats", title: "", preset: "contacts", kinds: PERSONAL, chats: [], leaves: ["archived"], excluded: [] },
  { id: "groups", title: "", preset: "groups", kinds: ["groups"], chats: [], leaves: ["archived"], excluded: [] },
  { id: "channels", title: "", preset: "channels", kinds: ["channels"], chats: [], leaves: ["archived"], excluded: [] },
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
  return { contacts: t("Chats"), nonContacts: t("Chats"), groups: t("Groups"), channels: t("Channels") }[f.preset] || f.title;
}

/** What a conversation is to the folders (iOS MTChatFolders.kind): a pair stands for both its kinds, Windows keeps no book. */
const kindsOf = (r) => (r.kind === "c" ? ["channels"] : r.kind === "g" || r.group ? ["groups"] : PERSONAL);
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

/** THE FOLDERS' PAGE (iOS MTFolderSettingsPage): what folders are for, a new one, the folders with the count of their chats -- All
 *  among them and never taken away -- each moved up or down or taken away, and the folders iOS recommends. */
export function FoldersPage({ onClose, opening = {} }) {
  const folders = useFolders();
  const [rows, setRows] = useState([]);
  const [editing, setEditing] = useState(null);
  const [adding, setAdding] = useState(false);   // the folder's chats picked at once (the tab's «Add Chats»)
  useEffect(() => { invoke("chats").then(setRows).catch(() => {}); }, []);
  // THE MENU'S WAY IN (iOS MTChatFolders.opening): a folder's page, or its chats to pick, once the folders are read
  const opened = useRef(false);
  useEffect(() => {
    const id = opening.edit || opening.add;
    if (opened.current || !id) return;
    loadFolders().then((all) => {
      const f = all.find((x) => x.id === id);
      if (!f || opened.current) return;
      opened.current = true;
      setAdding(!!opening.add);
      setEditing(f);
    });
  }, []);
  const put = (list) => saveFolders(list);
  const move = (i, d) => { const l = [...folders]; [l[i], l[i + d]] = [l[i + d], l[i]]; put(l); };
  const offered = [
    { id: "unread", title: t("Unread"), words: t("New messages from all chats."), f: { kinds: [...PERSONAL, "groups", "channels"], leaves: ["read", "archived"] } },
    { id: "personal", title: t("Personal"), words: t("Only messages from personal chats."), f: { kinds: PERSONAL, leaves: ["archived"] } },
    { id: "groups", title: t("Groups"), words: t("Only messages from groups."), f: { preset: "groups", kinds: ["groups"], leaves: ["archived"] } },
    { id: "channels", title: t("Channels"), words: t("Only messages from channels."), f: { preset: "channels", kinds: ["channels"], leaves: ["archived"] } },
  ].map((s) => ({ ...s, f: { ...fresh(), ...s.f } })).filter((s) => !folders.some((f) => alike(f, s.f)));
  if (editing) {
    return <FolderEdit folder={editing} rows={rows} isNew={!folders.some((f) => f.id === editing.id)} adding={adding}
                       onClose={() => { setEditing(null); setAdding(false); }}
                       onKeep={(f) => { put(folders.some((x) => x.id === f.id) ? folders.map((x) => (x.id === f.id ? f : x)) : [...folders, f]); setEditing(null); }} />;
  }
  return (
    <Page title={t("Folders")} onClose={onClose} back>
      <div className="folders-intro"><FolderGlyph size={64} color="#fff" />
        <span>{t("Create folders for different groups of chats and quickly switch between them.")}</span></div>
      <Section head={t("Folders")}>
        <button className="set-row accent" onClick={() => setEditing(fresh())}>
          <Glyph name="plus" size={18} color="var(--blue)" /><span className="row-title" style={{ color: "var(--blue)" }}>{t("Create a Folder")}</span>
        </button>
        {folders.map((f, i) => (
          <div key={f.id} className="set-row member">
            <button className="folder-name" onClick={() => f.id !== ALL && setEditing(f)} aria-label={folderTitle(f)}>{folderTitle(f)}</button>
            {f.id !== ALL && <span className="row-value">{rows.filter((r) => !r.blocked && takes(f, r)).length || ""}</span>}
            <button className="glass-mark small" disabled={i === 0} onClick={() => move(i, -1)} aria-label={`${t("Reorder")}: ${folderTitle(f)} ↑`}>↑</button>
            <button className="glass-mark small" disabled={i === folders.length - 1} onClick={() => move(i, 1)} aria-label={`${t("Reorder")}: ${folderTitle(f)} ↓`}>↓</button>
            {f.id !== ALL && (
              <button className="glass-mark small" onClick={() => put(folders.filter((x) => x.id !== f.id))} aria-label={`${t("Delete")}: ${folderTitle(f)}`}>
                <Glyph name="trash" size={14} color="var(--red)" />
              </button>
            )}
          </div>
        ))}
      </Section>
      {offered.length > 0 && (
        <Section head={t("Recommended Folders")}>
          {offered.map((s) => (
            <button key={s.id} className="set-row" aria-label={s.title}
                    onClick={() => put([...folders, { ...s.f, title: s.f.preset ? "" : s.title }])}>
              <span className="row-title"><span>{s.title}</span><span className="row-caption">{s.words}</span></span>
              <Glyph name="plus" size={18} color="var(--blue)" />
            </button>
          ))}
        </Section>
      )}
    </Page>
  );
}

const TYPES = [["contacts", "Personal", "personCircle"], ["groups", "Groups", "contacts"], ["channels", "Channels", "antenna"]];
const STATES = [["muted", "Muted", "bellSlash"], ["read", "Read", "markRead"], ["archived", "Archived", "archive"]];

/** A FOLDER'S PAGE (iOS MTFolderEditPage): its name, the chats it takes -- kinds and conversations -- and the chats it leaves out
 *  -- states and conversations, each line with its cross; «Done» keeps it once it has a name and takes something. */
function FolderEdit({ folder, rows, isNew, adding, onClose, onKeep }) {
  const [draft, setDraft] = useState(folder);
  const [name, setName] = useState(isNew ? "" : folderTitle(folder));
  const [picking, setPicking] = useState(adding ? "in" : null);   // "in" | "out"
  const typed = name.trim();
  const canKeep = typed && (draft.kinds.length > 0 || draft.chats.length > 0);
  const keep = () => {
    const f = { ...draft };
    if (!isNew && !folder.title && typed === folderTitle(folder)) f.title = "";   // a first folder keeps following the language
    else { f.title = typed; delete f.preset; }
    onKeep(f);
  };
  const nameOf = (ref) => rowTitle(ref, (rows.find((r) => r.ref === ref) || {}).name || ref.slice(0, 10));
  if (picking) return <FolderPicker taking={picking === "in"} folder={draft} rows={rows} onDone={(f) => { setDraft(f); setPicking(null); }} />;
  const typeLine = (k) => {
    const [, word, glyph] = [...TYPES, ...STATES].find((x) => x[0] === k) || [k, k, "circle"];
    return <><Glyph name={glyph} size={18} color="#fff" /><span className="row-title">{t(word)}</span></>;
  };
  const shownKinds = draft.kinds.filter((k) => k !== "nonContacts" || !draft.kinds.includes("contacts")).map((k) => (k === "nonContacts" ? "contacts" : k));
  return (
    <Page title={isNew ? t("New Folder") : t("Edit Folder")} onClose={onClose} back
          right={<button className="glass-mark" disabled={!canKeep} onClick={keep} aria-label={t("Done")}><Glyph name="tick" size={18} color={canKeep ? "#fff" : "#555"} /></button>}>
      <Section head={t("Folder Name")}>
        <input className="set-field" placeholder={t("Folder Name")} value={name} maxLength={12 * 4} aria-label={t("Folder Name")} onChange={(e) => setName(e.target.value)} />
      </Section>
      <Section head={t("Included Chats")} foot={t("Choose chats and types of chats that will appear in this folder.")}>
        <button className="set-row accent" onClick={() => setPicking("in")}><Glyph name="plus" size={18} color="var(--blue)" />
          <span className="row-title" style={{ color: "var(--blue)" }}>{t("Add Chats")}</span></button>
        {[...new Set(shownKinds)].map((k) => (
          <div key={k} className="set-row">{typeLine(k)}
            <button className="glass-mark small" aria-label={`${t("Delete")}: ${t((TYPES.find((x) => x[0] === k) || [])[1] || k)}`}
                    onClick={() => setDraft({ ...draft, kinds: draft.kinds.filter((x) => (k === "contacts" ? !PERSONAL.includes(x) : x !== k)) })}>
              <Glyph name="close" size={12} color="#fff" /></button>
          </div>
        ))}
        {draft.chats.map((c) => (
          <div key={c} className="set-row"><Face chat={c} size={28} /><span className="row-title">{nameOf(c)}</span>
            <button className="glass-mark small" aria-label={`${t("Delete")}: ${nameOf(c)}`} onClick={() => setDraft({ ...draft, chats: draft.chats.filter((x) => x !== c) })}>
              <Glyph name="close" size={12} color="#fff" /></button>
          </div>
        ))}
      </Section>
      <Section head={t("Excluded Chats")} foot={t("Choose chats and types of chats that will never appear in this folder.")}>
        <button className="set-row accent" onClick={() => setPicking("out")}><Glyph name="plus" size={18} color="var(--blue)" />
          <span className="row-title" style={{ color: "var(--blue)" }}>{t("Add Chats to Exclude")}</span></button>
        {draft.leaves.map((k) => (
          <div key={k} className="set-row">{typeLine(k)}
            <button className="glass-mark small" aria-label={`${t("Delete")}: ${t((STATES.find((x) => x[0] === k) || [])[1] || k)}`}
                    onClick={() => setDraft({ ...draft, leaves: draft.leaves.filter((x) => x !== k) })}><Glyph name="close" size={12} color="#fff" /></button>
          </div>
        ))}
        {draft.excluded.map((c) => (
          <div key={c} className="set-row"><Face chat={c} size={28} /><span className="row-title">{nameOf(c)}</span>
            <button className="glass-mark small" aria-label={`${t("Delete")}: ${nameOf(c)}`} onClick={() => setDraft({ ...draft, excluded: draft.excluded.filter((x) => x !== c) })}>
              <Glyph name="close" size={12} color="#fff" /></button>
          </div>
        ))}
      </Section>
    </Page>
  );
}

/** THE CHATS OF A FOLDER, CHOSEN (iOS MTFolderChatPicker): the kinds first -- or the states, for the chats left out -- then every
 *  conversation, each with its tick; a chat taken in is not left out, and the other way round. */
function FolderPicker({ taking, folder, rows, onDone }) {
  const [f, setF] = useState(folder);
  const [q, setQ] = useState("");
  const flipKind = (k) => {
    const keys = k === "contacts" ? PERSONAL : [k];
    const on = keys.every((x) => f.kinds.includes(x));
    setF({ ...f, kinds: on ? f.kinds.filter((x) => !keys.includes(x)) : [...new Set([...f.kinds, ...keys])] });
  };
  const flipLeave = (k) => setF({ ...f, leaves: f.leaves.includes(k) ? f.leaves.filter((x) => x !== k) : [...f.leaves, k] });
  const flipChat = (ref) => {
    if (taking) setF({ ...f, excluded: f.excluded.filter((x) => x !== ref), chats: f.chats.includes(ref) ? f.chats.filter((x) => x !== ref) : [...f.chats, ref] });
    else setF({ ...f, chats: f.chats.filter((x) => x !== ref), excluded: f.excluded.includes(ref) ? f.excluded.filter((x) => x !== ref) : [...f.excluded, ref] });
  };
  const shown = rows.filter((r) => !r.blocked && (!q.trim() || rowTitle(r.ref, r.name).toLowerCase().includes(q.trim().toLowerCase())));
  const tick = (on) => <span className={"pick-tick" + (on ? " on" : "")}>{on ? "✓" : ""}</span>;
  return (
    <Page title={taking ? t("Include Chats") : t("Exclude Chats")} onClose={() => onDone(folder)} back
          right={<button className="glass-mark" onClick={() => onDone(f)} aria-label={t("Done")}><Glyph name="tick" size={18} color="#fff" /></button>}>
      <input className="meet-field pick-search" placeholder={t("Search")} value={q} onChange={(e) => setQ(e.target.value)} aria-label={t("Search")} />
      {!q.trim() && (
        <Section head={t("Chat Types")}>
          {(taking ? TYPES : STATES).map(([k, word, glyph]) => {
            const on = taking ? (k === "contacts" ? PERSONAL.every((x) => f.kinds.includes(x)) : f.kinds.includes(k)) : f.leaves.includes(k);
            return (
              <button key={k} className="set-row" aria-pressed={on} aria-label={t(word)} onClick={() => (taking ? flipKind(k) : flipLeave(k))}>
                <Glyph name={glyph} size={18} color="#fff" /><span className="row-title">{t(word)}</span>{tick(on)}
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
              {r.ref === SAVED ? <SelfFace size={32} /> : <Face chat={r.ref} version={r.face} size={32} />}<span className="row-title">{rowTitle(r.ref, r.name)}</span>{tick(on)}
            </button>
          );
        })}
      </Section>
    </Page>
  );
}
