import { useEffect, useRef, useState } from "react";
import { useLeave } from "./leave.js";
import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { mtSize, t } from "./strings.js";
import { dropPictures } from "./caches.js";
import { CopyStack } from "./CopyPages.jsx";
import { Glyph } from "./TopBar.jsx";
import { TermsView } from "./Terms.jsx";
import { BlockedPage } from "./Safety.jsx";
import { PageGround } from "./Ground.jsx";
import { WallRules } from "./Wall.jsx";
import { FoldersPage } from "./Folders.jsx";
import { LookPage } from "./Look.jsx";
import { LevelsPage } from "./Levels.jsx";
import { CacheSection, HomeNodePage } from "./HomeNode.jsx";
import { QuestionsPage } from "./Questions.jsx";
import { sizeText } from "./Media.jsx";

/** How long a page takes to leave (iOS: a pop, a sheet's dismissal); none where the person asked for less motion. */
const LEAVE_MS = 260;
const still = () => { try { return window.matchMedia("(prefers-reduced-motion: reduce)").matches; } catch { return false; } };

/** A page over the app (iOS overlay with an inline title): the close cross or the back chevron, the title, the body. The rows run
 *  on under the bar to the window's top (iOS 26: the platform's own bar, its marks on their own glass) and fade there: the page's
 *  ground is drawn once more over them, solid at the top and gone at the bar's lower edge (the system's soft scroll edge).
 *  THE WAY IN AND OUT (iOS UINavigationController and the page sheet): a page with the back chevron is pushed -- it slides in from
 *  the right edge and back out to it; a page with the cross is a sheet -- it rises from the bottom and goes down. While it leaves
 *  it takes no touch and no reader sees it (inert). */
export function Page({ title, subtitle, onClose, back, right, children, ground, foot }) {
  const g = ground || <PageGround />;
  const [leaving, setLeaving] = useState(false);
  const leave = () => {
    if (leaving) return;
    if (still()) { onClose(); return; }
    setLeaving(true);
    setTimeout(onClose, LEAVE_MS);
  };
  useLeave(leave);   // Esc, the mouse's back button, Alt+← -- as its own back mark (iOS: the edge's stroke)
  return (
    <div className={"page-over " + (back ? "slides" : "rises") + (leaving ? " leaving" : "")} inert={leaving || undefined} role="dialog" aria-label={title}>
      {g}
      <div className="page-wash" aria-hidden="true">{g}</div>
      <header className="page-bar">
        <button className="glass-mark" onClick={leave} aria-label={back ? t("Back") : t("Close")}>
          <Glyph name={back ? "back" : "close"} size={18} color="var(--bar-glyph)" />
        </button>
        {/* the title's second line where iOS writes one (navigationSubtitle: the balance where coins leave) */}
        <div className="page-title">{title}{subtitle && <small className="page-subtitle digits">{subtitle}</small>}</div>
        <div className="page-right">{right}</div>
      </header>
      <div className={"page-list" + (foot ? " with-foot" : "")}>{children}</div>
      {/* what stands under the rows at the window's foot, out of their scroll (iOS: a bar under the List, as the comment's field) */}
      {foot && <div className="page-foot">{foot}</div>}
    </div>
  );
}

/** The ground of a sheet (iOS: a List on the system's grouped background, no page ground): black. */
export const SHEET_GROUND = <div className="ground-box sheet-ground" aria-hidden="true" />;

/** A section of the inset list on glass, its footer gray under it. */
export const Section = ({ head, foot, children }) => (
  <div className="sect">
    {head && <div className="sect-head">{head}</div>}
    <div className="sect-rows">{children}</div>
    {foot && <div className="sect-foot">{foot}</div>}
  </div>
);

/** A row of Settings (iOS settingsToggleLabel): the white glyph in a 29 coloured square, the title, a value or a chevron. */
export function Row({ icon, color, title, value, onClick, red, center, children }) {
  const inner = (
    <>
      {icon && <span className="row-icon" style={{ background: color }}><Glyph name={icon} size={17} color="#fff" /></span>}
      <span className={"row-title" + (red ? " red" : "") + (center ? " center" : "")}>{title}</span>
      {value != null && <span className="row-value">{value}</span>}
      {children}
      {onClick && !center && !children && <span className="row-chevron"><Glyph name="chevronRight" size={14} color="rgba(235,235,245,0.3)" /></span>}
    </>
  );
  return onClick ? <button className="set-row" onClick={onClick}>{inner}</button> : <div className="set-row">{inner}</div>;
}

export function Toggle({ icon, color, title, on, onChange, caption, disabled }) {
  return (
    <label className={"set-row toggle" + (disabled ? " off" : "")}>
      {icon && <span className="row-icon" style={{ background: color }}><Glyph name={icon} size={17} color="#fff" /></span>}
      <span className="row-title">{title}{caption && <span className="row-caption">{caption}</span>}</span>
      <input type="checkbox" role="switch" aria-label={title} checked={on} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

const GRAY = "#8e8e93", RED = "#ff3b30", INDIGO = "#5856d6", BLUE = "#0a84ff", CYAN = "#32ade6", GREEN = "#30d158",
  PINK = "#ff2d55", ORANGE = "#ff9500", TEAL = "#40c8e0", PURPLE = "#bf5af2";

/** SETTINGS (iOS SettingsTabView, MontanaSettings.swift 92-256): the words; notifications, data, privacy, language; the
 *  question, the terms, the privacy policy; your node, access by level, appearance. */
/** The version at the drawer's foot and under About Montana (iOS AppVersion.full: v<short> (<build>)). */
export const VERSION = "v0.1.0 (Windows)";
/** WHO PORTED THIS (the owner's word 24.10.2026): the Windows port's own credit, beside Montana's -- never the authorship of Montana. */
const PORTED = "Porting and adaptation from Montana iOS to Windows: DinetPDA — Linkora.";

export default function Settings({ onClose, onGone, start }) {
  const [page, setPage] = useState(start || null);   // a way straight in (the panel's first slot: the banners, the copy with contacts)
  const [dataSub, setDataSub] = useState(null);   // the copy's pages over Data and Storage: «chats» or «kinds»
  const [s, setS] = useState(null);
  const look = () => invoke("settings_get").then(setS);
  useEffect(() => { look(); }, []);
  const set = (key, value) => invoke("setting_set", { key, value }).then(look);
  const on = (v) => v !== false;
  if (!s) return null;
  const sub = (p) => () => setPage(p);
  const back = () => setPage(null);

  if (page === "seed") return <SeedShow onClose={back} />;
  if (page === "folders") return <FoldersPage onClose={back} />;
  if (page === "look") return <LookPage onClose={back} />;
  if (page === "levels") return <LevelsPage onClose={back} />;
  if (page === "node") return <HomeNodePage onClose={back} />;
  if (page === "questions") return <QuestionsPage onClose={back} />;
  if (page === "terms") return <Page title={t("Terms of Use")} onClose={back} back><TermsView /></Page>;
  if (page === "notifications") {
    return (
      <Page title={t("Notifications")} onClose={back} back>
        <Section>
          <Row icon="bell" color={RED} title={t("Allow notifications")} onClick={() => invoke("open_site", { page: "notifications" })} />
        </Section>
        <Section>
          <Toggle icon="bell" color={PINK} title={t("Sound")} on={on(s.notifSound)} onChange={(v) => set("notifSound", v)} caption={t("Notifications of new messages play a sound. Off, they arrive silently.")} />
          <Toggle icon="textDoc" color={GREEN} title={t("Show message text")} on={on(s.notifPreview)} onChange={(v) => set("notifPreview", v)} caption={t("A notification shows the words of the message. Off, it shows none of them.")} />
          <Toggle icon="personCircle" color={ORANGE} title={t("Show sender")} on={on(s.notifSender)} onChange={(v) => set("notifSender", v)} caption={t("A notification of a message shows who wrote and their photo. Off, it reads Montana instead.")} />
        </Section>
      </Page>
    );
  }
  if (page === "data" && dataSub) return <CopyStack start={dataSub} onClose={() => setDataSub(null)} />;
  if (page === "data") {
    return (
      <Page title={t("Data and Storage")} onClose={back} back>
        {/* iOS DataStorageView, in its order: auto-download, the picture cache, the cache, what this computer holds, the backup,
            the copy with contacts (iCloud's SYNC has no Windows counterpart: the copy is a .mtbak file) */}
        <Section head={t("MEDIA AUTO-DOWNLOAD")} foot={t("When off, an attachment shows a download button and is fetched on tap.")}>
          <Toggle icon="antenna" color={GREEN} title={t("Over mobile network")} on={on(s.autoDownloadCellular)} onChange={(v) => set("autoDownloadCellular", v)} />
          <Toggle icon="wifi" color={BLUE} title={t("Over Wi-Fi")} on={on(s.autoDownload)} onChange={(v) => set("autoDownload", v)} />
        </Section>
        <PictureCache />
        <CacheSection />
        <OnThisComputer onKinds={() => setDataSub("kinds")} />
        <Backup onOpen={setDataSub} />
        <Keeping />
      </Page>
    );
  }
  if (page === "privacy") return <Privacy s={s} set={set} onBack={back} onSeed={sub("seed")} onGone={onGone} />;
  if (page === "language") {
    const pick = (v) => set("AppLanguage", v).then(() => window.location.reload());
    return (
      <Page title={t("Language")} onClose={back} back>
        <Section foot={t("Changing the language applies at once.")}>
          {[["", t("System"), ""], ["en", "English", "English"], ["ru", "Русский", t("Russian")]].map(([k, a, b]) => (
            <button key={k} className="set-row lang" onClick={() => pick(k)}>
              <span className="lang-words"><span>{a}</span>{b && <span className="row-caption">{b}</span>}</span>
              {s.AppLanguage === k && <Glyph name="tick" size={18} color="var(--green)" />}
            </button>
          ))}
        </Section>
      </Page>
    );
  }
  if (page === "ask") {
    return (
      <Page title={t("Ask a question")} onClose={back} back>
        <Section head={t("Write to us")} foot={t("Reports of objectionable content are reviewed within 24 hours.")}>
          <Row title={t("Ask a question")} onClick={() => invoke("open_site", { page: "mail" })} />
          <Row title={t("Site")} onClick={() => invoke("open_site", { page: "site" })} />
          <Row title={t("Guide")} onClick={() => invoke("open_site", { page: "guide" })} />
        </Section>
      </Page>
    );
  }
  return (
    <Page title={t("Settings")} onClose={onClose}>
      <Section foot={t("Write down the 24 words and keep them: on a new device your identity and your saved history open only from them.")}>
        <Row icon="key" color={GRAY} title={t("Save 24 words")} onClick={sub("seed")} />
      </Section>
      <Section>
        <Row icon="bell" color={RED} title={t("Notifications and Sounds")} onClick={sub("notifications")} />
        <Row icon="chats" color={BLUE} title={t("Chat Folders")} onClick={sub("folders")} />
        <Row icon="download" color={INDIGO} title={t("Data and Storage")} onClick={sub("data")} />
        <Row icon="server" color={GRAY} title={t("Your node")} onClick={sub("node")} />
        <Row icon="lock" color={GRAY} title={t("Privacy")} onClick={sub("privacy")} />
        <Row icon="trianglePath" color={ORANGE} title={t("Access by level")} onClick={sub("levels")} />
        <Row icon="photo" color={BLUE} title={t("Appearance")} onClick={sub("look")} />
        <Row icon="globe" color={CYAN} title={t("Language")} onClick={sub("language")} />
      </Section>
      <Section>
        <Row icon="help" color={GREEN} title={t("Questions")} onClick={sub("questions")} />
        <Row icon="help" color={BLUE} title={t("Ask a question")} onClick={sub("ask")} />
        <Row icon="textDoc" color={GRAY} title={t("Terms of Use")} onClick={sub("terms")} />
        <Row icon="hand" color={BLUE} title={t("Privacy Policy")} onClick={() => invoke("open_site", { page: "privacy" })} />
      </Section>
      {/* ABOUT MONTANA (the owner's word 24.10.2026): the version, and under it in the footer's small grey type the port's credit --
          one line, no screen of its own */}
      <Section head={t("About Montana")} foot={PORTED}>
        <div className="set-row" role="group" aria-label={`Montana ${VERSION}`}><span className="row-title">Montana</span><span className="row-value digits">{VERSION}</span></div>
      </Section>
    </Page>
  );
}

/** THE COPY (iOS DataStorageView «BACKUP»): made under the words into Downloads\Montana; laid back from a file; and the copy
 *  another device of these words left on the nodes taken back. What came back is counted, never promised. */
/** THE COPY WITH CONTACTS (iOS MTKeepingSection): two switches, what a keeper learns said beneath them, the state in the keepers'
 *  own words (a part is «held» only on its keeper's «held»), the parts this computer holds by name and size, the road back. */
function Keeping() {
  const [k, setK] = useState(null);
  const look = () => invoke("keep_state").then(setK).catch(() => {});
  useEffect(() => {
    look();
    let stop = null, gone = false;
    listen("montana://keeping", look).then((u) => { if (gone) u(); else stop = u; });
    const tick = setInterval(look, 3000);
    return () => { gone = true; stop && stop(); clearInterval(tick); };
  }, []);
  if (!k || !k.agrees) return null;
  const act = (a, extra = {}) => invoke("keep_do", { act: a, ...extra }).then(look);
  const mine = k.mine && k.told;
  const state = k.asking ? t("Asking the people you write to…")
    : !k.keepers ? t(k.short ? "None of your contacts can keep a part yet" : "Not kept yet")
    : t("Kept by %lld of %lld").replace("%lld", k.held).replace("%lld", k.keepers);
  const tk = k.taking || { s: "idle" };
  const busy = tk.s === "calling" || tk.s === "laying";
  const taking = tk.s === "calling" ? (tk.need > 0 ? t("Parts in hand: %lld of %lld").replace("%lld", tk.have).replace("%lld", tk.need) : t("Restoring the identity chain"))
    : tk.s === "laying" ? t("Restoring…") : tk.s === "done" ? t("The copy came back") : tk.s === "failed" ? t("No copy came back") : null;
  return (
    <>
      <Section head={t("COPY WITH CONTACTS")} foot={t(KEEP_FOOT)}>
        <Toggle icon="contacts" color={CYAN} title={t("Keep my copy with my contacts")} on={mine} onChange={(v) => act("mine", { on: v })} />
        {mine && <div className="set-row"><span className="row-title"><span className="row-caption">{state}</span></span></div>}
      </Section>
      <Section foot={t("Parts of other people's copies are sealed: this computer cannot open them, and each goes back only to its owner's words.")}>
        <Toggle icon="archive" color={GRAY} title={t("Keep parts for my contacts")} on={k.others} onChange={(v) => act("others", { on: v })} />
        {k.kept.map((x) => (
          <div key={x.chat} className="set-row kept">
            <span className="row-title">{x.name}<span className="row-caption">{sizeText(x.bytes)}</span></span>
            <button className="row-act red" onClick={() => act("drop", { chat: x.chat })} aria-label={`${t("Stop keeping this part")}: ${x.name}`}>{t("Stop keeping this part")}</button>
          </div>
        ))}
        <Row icon="download" color={BLUE} title={t("Take my copy back from my contacts")} onClick={busy ? undefined : () => act("take")} />
        {taking && <div className="set-row" role="status"><span className="row-title"><span className="row-caption">{taking}</span></span></div>}
      </Section>
    </>
  );
}

const KEEP_FOOT = "Your copy is sealed with your 24 words and cut into parts. The people you write to keep the parts around a ring, each part with two of them: they see only its size and when it changes, and cannot open it. With your words on a new device, the parts come back from them, and each of them gives back the conversation you share.";

/** THE QUESTION AT THE OPENING (iOS keepAsk; the author's word 08.10.2026 23:2x MSK: «on by default, and a question at the
 *  opening»): asked once, on the list's own plate rather than over the window; nothing leaves before the person is told. */
export function KeepAsk() {
  const [k, setK] = useState(null);
  useEffect(() => { invoke("keep_state").then(setK).catch(() => {}); }, []);
  if (!k || k.told || !k.agrees) return null;
  const answer = (keep) => { invoke("keep_do", { act: "told", on: keep }).catch(() => {}); setK({ ...k, told: true }); };
  return (
    <div className="keep-ask" role="group" aria-label={t("Keep your copy with your contacts?")}>
      <b>{t("Keep your copy with your contacts?")}</b>
      <span>{t(KEEP_FOOT)}</span>
      <div className="keep-ask-keys">
        <button onClick={() => answer(false)}>{t("Not now")}</button>
        <button className="yes" onClick={() => answer(true)}>{t("Keep")}</button>
      </div>
    </div>
  );
}

/** THE PICTURE CACHE (iOS DataStorageView «PICTURE CACHE», MontanaCaches.dropAll): the pictures the window keeps in memory, let go
 *  by one tap -- a picture standing on the screen stays until it leaves; a mark says it was done. */
function PictureCache() {
  const [done, setDone] = useState(false);
  const clear = () => {
    const n = dropPictures();
    invoke("trace", { line: `caches cleared=${n} by=person` }).catch(() => {});
    setDone(true);
  };
  return (
    <Section head={t("PICTURE CACHE")} foot={t("Pictures are kept in memory so chats and walls open without waiting. They stay until you clear them here.")}>
      <button className="set-row" onClick={clear} aria-label={t("Clear")}>
        <span className="row-icon" style={{ background: GRAY }}><Glyph name="photo" size={17} color="#fff" /></span>
        <span className="row-title">{t("Clear")}</span>
        {done && <span className="row-mark" role="img" aria-label={t("Done")}><Glyph name="tick" size={17} color="var(--gray)" /></span>}
      </button>
    </Section>
  );
}

/** WHAT THIS COMPUTER HOLDS, MEASURED ON ITS DISK (iOS DataStorageView «ON THIS PHONE», MTDiskUse; the author's word 18.10.2026
 *  10:2x MSK): every row in its own colour, each file counted once; the copies waiting and the files opened are cleared here,
 *  each after its question; the sum at the foot. */
function OnThisComputer({ onKinds }) {
  const [u, setU] = useState(null);
  const [asking, setAsking] = useState(null);   // "shelf" | "opened"
  const [word, setWord] = useState(null);
  const measure = () => invoke("disk_use").then(setU).catch(() => {});
  useEffect(() => { measure(); }, []);
  const clear = (what) => {
    setAsking(null);
    invoke("disk_clear", { what })
      .then((r) => { if (what === "opened") setWord(t("Freed %@. Files back in your chats: %lld.").replace("%@", mtSize(r.freed)).replace("%lld", r.back)); })
      .catch(() => {})
      .finally(measure);
  };
  const row = (title, icon, color, bytes, what, open) => {
    const inner = (
      <>
        <span className="row-icon" style={{ background: color }}><Glyph name={icon} size={17} color="#fff" /></span>
        <span className="row-title">{title}</span>
        <span className="row-value">{mtSize(bytes)}</span>
        {open && <span className="row-chevron"><Glyph name="chevronRight" size={14} color="rgba(235,235,245,0.3)" /></span>}
      </>
    );
    // the attachments and the files no letter names open the copy's kinds (iOS NavigationLink → CopyKindsPage)
    if (open) return <button className="set-row" key={title} onClick={open} aria-label={`${title}: ${mtSize(bytes)}`}>{inner}</button>;
    return (
      <div className="set-row" key={title} role="group" aria-label={`${title}: ${mtSize(bytes)}`}>
        {inner}
        {what && (
          <button className="row-trash" disabled={!bytes} onClick={() => setAsking(what)} aria-label={`${t("Clear")}: ${title}`}>
            <Glyph name="trash" size={18} color="var(--red)" />
          </button>
        )}
      </div>
    );
  };
  const asked = asking === "shelf"
    ? [t("Clear the copies waiting on this computer?"), t("The copies made for your node and your keepers, on their way, leave this computer; the next round makes them again.")]
    : [t("Clear opened files?"), t("Copies written out when you opened a file from your chats. Each file stays in its chat and opens again from there.")];
  return (
    <>
      <Section head={t("ON THIS COMPUTER")} foot={t("Measured on this computer's disk, each file once.")}>
        {!u ? <div className="set-row" role="status"><span className="spinner small center" /></div> : <>
          {row(t("Attachments of chats"), "attach", INDIGO, u.chats, null, onKinds)}
          {row(t("Files no letter names"), "doc", GRAY, u.unnamed, null, onKinds)}
          {row(t("Pictures of walls"), "grid", TEAL, u.walls)}
          {row(t("Copies waiting on this computer"), "archive", ORANGE, u.shelf, "shelf")}
          {row(t("Kept for the people who write to you"), "people", GREEN, u.kept)}
          {row(t("Opened files"), "copy", PURPLE, u.opened, "opened")}
          {row(t("History of chats"), "history", BLUE, u.history)}
          {row(t("Faces"), "personCircle", PINK, u.faces)}
          {row(t("The rest"), "more", GRAY, u.other)}
          <div className="set-row total" role="group" aria-label={`${t("On this computer")}: ${mtSize(u.total)}`}>
            <span className="row-title">{t("On this computer")}</span>
            <span className="row-value">{mtSize(u.total)}</span>
          </div>
        </>}
      </Section>
      {asking && (
        // iOS: a confirmationDialog with its title shown -- the platform's action sheet from below
        <div className="sheet-shade" onClick={() => setAsking(null)}>
          <div className="action-sheet" onClick={(e) => e.stopPropagation()} role="alertdialog" aria-label={asked[0]}>
            <div className="action-group">
              <div className="action-title"><b>{asked[0]}</b>{asked[1]}</div>
              <button className="action red" onClick={() => clear(asking)}>{t("Clear")}</button>
            </div>
            <button className="action cancel" onClick={() => setAsking(null)}>{t("Cancel")}</button>
          </div>
        </div>
      )}
      {word && (
        <div className="alert-shade" role="alertdialog" aria-label={t("Cache")}>
          <div className="alert">
            <b>{t("Cache")}</b>
            <p>{word}</p>
            <div className="alert-keys"><button className="bold" onClick={() => setWord(null)}>{t("OK")}</button></div>
          </div>
        </div>
      )}
    </>
  );
}

/** THE BACKUP (iOS DataStorageView «BACKUP»): make a copy, take one back, and what the copy takes, counted from this computer --
 *  the conversations, their records, the attachments and their size. */
function Backup({ onOpen }) {
  const [busy, setBusy] = useState(null);
  const [made, setMade] = useState(null);
  const [back, setBack] = useState(null);
  const [inv, setInv] = useState(null);
  const picker = useRef(null);
  const count = () => invoke("copy_inventory").then(setInv).catch(() => {});
  useEffect(() => {
    count();
    let stop = null, gone = false;
    listen("montana://restored", (e) => { setBusy(null); setBack(e.payload); count(); }).then((u) => { if (gone) u(); else stop = u; });
    return () => { gone = true; stop && stop(); };
  }, []);
  const make = async () => {
    setBusy("make"); setMade(null);
    try { setMade(await invoke("history_copy")); } catch (e) { setMade({ error: String(e) }); }
    setBusy(null);
  };
  const restore = async (file) => {
    setBusy("restore"); setBack(null);
    invoke("history_restore", new Uint8Array(await file.arrayBuffer())).catch(() => setBusy(null));
  };
  return (
    <Section head={t("BACKUP")} foot={t("The copy holds every conversation and attachment of this device and is sealed with a key your 24 words open. Keep the words: without them nobody can read the copy — you neither.")}>
      <input ref={picker} type="file" accept=".mtbak" hidden onChange={(e) => { if (e.target.files[0]) restore(e.target.files[0]); e.target.value = ""; }} />
      <Row icon="upload" color={GREEN} title={busy === "make" ? t("Sealing the copy…") : t("Create backup…")} onClick={busy ? undefined : make} />
      <Row icon="download" color={ORANGE} title={busy === "restore" ? t("Restoring…") : t("Restore from backup…")} onClick={busy ? undefined : () => picker.current.click()} />
      {made && <div className="set-row"><span className="row-title"><span className="row-caption">{made.error ? t("The copy was not made") : made}</span></span></div>}
      {back && (back.error
        ? <div className="set-row"><span className="row-title red">{back.error === "Unopened" ? t("These words do not open this copy.") : t("The copy is torn.")}</span></div>
        : <div className="set-row" role="status"><span className="row-title"><span className="row-caption">
            {t("Taken into this device: %lld conversations, %lld records, %lld attachments.").replace("%lld", back.chats).replace("%lld", back.records).replace("%lld", back.media)}
          </span></span></div>)}
      {/* what the copy takes, by the person's plan; every row opens what is inside (iOS: NavigationLink → CopyChatsPage, CopyKindsPage) */}
      {inv && <>
        <Row icon="chats" color={BLUE} title={t("Conversations")} value={`${inv.chats} / ${inv.convs}`} onClick={() => onOpen("chats")} />
        <Row icon="textDoc" color={TEAL} title={t("Records")} value={String(inv.letters)} onClick={() => onOpen("chats")} />
        <Row icon="attach" color={INDIGO} title={t("Attachments")} value={`${inv.files} · ${mtSize(inv.bytes)}`} onClick={() => onOpen("kinds")} />
      </>}
    </Section>
  );
}

/** PRIVACY (iOS PrivacyView): read receipts; the seed phrase; the account's deletion behind its alert. */
function Privacy({ s, set, onBack, onSeed, onGone }) {
  const [ask, setAsk] = useState(false);
  const [blocked, setBlocked] = useState(false);
  const [wall, setWall] = useState(false);
  const [coins, setCoins] = useState(true);   // iOS MTCoinShow: the balance at my face and in my presence words
  useEffect(() => { invoke("coins_shown", {}).then(setCoins).catch(() => {}); }, []);
  if (blocked) return <BlockedPage onClose={() => setBlocked(false)} />;
  if (wall) return <WallRules onClose={() => setWall(false)} />;
  return (
    <Page title={t("Privacy")} onClose={onBack} back>
      <Section>
        <Toggle icon="personCircle" color="#30b0c7" title={t("Online status")} on={s.presenceSharing !== false}
                onChange={(v) => set("presenceSharing", v)}
                caption={t("Only whether others see you online. Walls and pages come and go regardless.")} />
        <Toggle icon="tick" color={GREEN} title={t("Read receipts")} on={s.readReceiptsEnabled !== false} onChange={(v) => set("readReceiptsEnabled", v)}
                caption={t("People see that you have read their messages, and channel owners count your views. Off, nobody is told.")} />
        <Toggle icon="link" color={BLUE} title={t("Link previews")} on={s.linkPreviewsEnabled !== false} onChange={(v) => set("linkPreviewsEnabled", v)}
                caption={t("Your computer reads the page of a link you send, so that site sees this computer.")} />
      </Section>
      <Section foot={t("Your level is your reputation and is always visible. You can hide your balance here.")}>
        <Toggle icon="wallet" color={ORANGE} title={t("Show my coins")} on={coins} onChange={(v) => invoke("coins_shown", { on: v }).then(setCoins)} />
      </Section>
      <Section>
        <Toggle icon="nosign" color="#af52de" title={t("Filter objectionable content")} on={s.objectionableFilterOn !== false}
                onChange={(v) => set("objectionableFilterOn", v)} caption={t("Messages, wall posts and comments from others with offensive words stay folded until you tap them.")} />
        <Row icon="hand" color={RED} title={t("Blocked users")} onClick={() => setBlocked(true)} />
        <Row icon="textDoc" color={INDIGO} title={t("Wall")} onClick={() => setWall(true)} />
      </Section>
      <Section>
        <Row icon="key" color={GRAY} title={t("Seed phrase")} onClick={onSeed} />
      </Section>
      <Section>
        <Row title={t("Delete account")} red center onClick={() => setAsk(true)} />
      </Section>
      {ask && (
        <div className="alert-shade" onClick={() => setAsk(false)}>
          <div className="alert wide" role="alertdialog" aria-label={t("Delete account?")} onClick={(e) => e.stopPropagation()}>
            <div className="alert-title">{t("Delete account?")}</div>
            <div className="alert-text">{t("DELETE_ACCOUNT_MESSAGE")}</div>
            <button onClick={() => { setAsk(false); onSeed(); }}>{t("Show seed phrase")}</button>
            <button className="red" onClick={async () => {
              // the person's own values of this window leave with them (iOS dataKeys: the training game, the chats' grounds); the
              // program then starts again and the leaving is carried out before anything reads the folder (forgotten.rs)
              try {
                Object.keys(localStorage).filter((k) => k === "chess.computer.game" || k.startsWith("chatWall.")).forEach((k) => localStorage.removeItem(k));
              } catch { /* a window without its storage keeps nothing of the person */ }
              await invoke("account_delete");
              onGone();
            }}>{t("Delete account")}</button>
            <button className="bold" onClick={() => setAsk(false)}>{t("Cancel")}</button>
          </div>
        </div>
      )}
    </Page>
  );
}

/** THE SECRET PHRASE (iOS SeedShowView, MontanaScreens.swift 430-541): the device's own check (Windows Hello), the warning
 *  with its two promises, then the 24 words in two columns, 1-12 and 13-24. */
export function SeedShow({ onClose }) {
  const [words, setWords] = useState(null);
  const [problem, setProblem] = useState(null);
  const [ok, setOk] = useState([false, false]);
  const [shown, setShown] = useState(false);
  const [copied, setCopied] = useState(false);
  const unlock = async () => {
    setProblem(null);
    try {
      setWords(await invoke("seed_reveal"));
    } catch (e) {
      const k = String(e);
      setProblem(k === "notset" ? t("Set a passcode on this device — without it there is nothing to protect the phrase with.")
        : k === "none" ? t("No active seed found.") : t("Confirmation failed."));
    }
  };
  useEffect(() => { unlock(); }, []);
  const copy = async () => { if (await invoke("identity_copy_words")) { setCopied(true); setTimeout(() => setCopied(false), 2000); } };
  return (
    <Page title={t("Secret phrase")} onClose={onClose} back>
      {!words && (
        <div className="seed-lock">
          <Glyph name="lock" size={44} color="#fff" />
          <div className="seed-note">{problem || t("Confirm with the device passcode or biometrics to see the secret phrase.")}</div>
          <button className="seed-unlock" onClick={unlock}>{t("Unlock")}</button>
        </div>
      )}
      {words && !shown && (
        <div className="seed-warn">
          <Glyph name="shield" size={72} color="#fff" />
          <div className="seed-only">⚠︎ {t("Information only for you!")}</div>
          <div className="seed-title">{t("This seed phrase unlocks access to your wallet")}</div>
          {[t("Montana has no access to this key."), t("Do not keep it in digital form; write it on paper and keep it in a safe place.")].map((p, i) => (
            <button key={i} className={"seed-check" + (ok[i] ? " on" : "")} onClick={() => setOk(ok.map((x, j) => (j === i ? !x : x)))}>
              <span className="box">{ok[i] ? "✓" : ""}</span><span>{p}</span>
            </button>
          ))}
          <button className="seed-go" disabled={!ok[0] || !ok[1]} onClick={() => setShown(true)}>{t("Continue")}</button>
        </div>
      )}
      {words && shown && (
        <div className="seed-words">
          <div className="seed-note">{t("Write these 24 words down in order and keep them offline. They restore the history if you lose all your devices. Show them to no one.")}</div>
          <div className="seed-grid">
            {words.map((_, i) => {
              const n = i % 2 === 0 ? i / 2 : 12 + (i - 1) / 2;   // column-major: 1-12 left, 13-24 right
              return <div key={i} className="word"><span className="word-n">{n + 1}.</span><b>{words[n]}</b></div>;
            })}
          </div>
          <button className={"copy-link" + (copied ? " done" : "")} onClick={copy}>
            <Glyph name={copied ? "tick" : "copy"} size={14} />{copied ? t("Copied") : t("Copy")}
          </button>
        </div>
      )}
    </Page>
  );
}
