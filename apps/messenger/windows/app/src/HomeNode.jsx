import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { mtSize, t } from "./strings.js";
import { Page, Row, Section, Toggle } from "./Settings.jsx";
import { Glyph } from "./TopBar.jsx";

const GRAY = "#8e8e93", BLUE = "#0a84ff", GREEN = "#30d158", ORANGE = "#ff9500";
/** A format filled as iOS's String(format:) fills it: each %lld or %@ takes the next value, a %N$lld the Nth. */
const fmt = (s, ...v) => { let i = 0; return s.replace(/%(?:(\d+)\$)?(?:lld|@)/g, (_, k) => String(v[k ? k - 1 : i++])); };
/** What a node names it can do (iOS HomeNodeView.capWords), in iOS's order, each with its glyph. */
const CAPS = [["vault", "Copies of the whole computer", "server"], ["home", "Your files", "photo"], ["box", "Letters for sleeping phones", "archive"],
  ["blob", "Attachments in transit", "attach"], ["signal", "Call signalling", "phone"], ["turn", "Call relay", "callOut"], ["diag", "Diaries", "textDoc"],
  ["stun", "Reflector", "antenna"], ["notify", "Wakes", "bellFill"], ["gif", "Moving pictures", "gallery"], ["name", "Names", "at"]];
/** A size as the platform says it (iOS mtSize). */
export const size = (b) => mtSize(b);
/** EVERY REFUSAL IS SPOKEN, BY ONE READING (iOS MontanaBackup.Refusal.spoken(by: .node)). */
export function spoken(why) {
  if (why === "empty") return t("Your node holds no copy yet.");
  if (why === "stopped") return t("Stopped.");
  if (why === "noSeed") return t("This device holds no identity yet. Enter your 24 words first, then restore.");
  if (why === "Unopened") return t("These 24 words do not open this file: it is a backup of another phrase, or not a Montana backup at all.");
  if (why === "Torn") return t("This backup is cut short or damaged. Whatever could be read has been filed.");
  if (why === "disk") return t("The disk refused: %@").replace("%@", why);
  return t("Your node did not take the copy: %@").replace("%@", why);
}

/** THE CACHE, CLEARED AS THE REFERENCE CLEARS IT (iOS DataStorageView's CACHE, the author's word 18.10.2026 20:1x MSK): what the
 *  person's own node holds leaves this computer, and comes back from the node at a look or a tap -- the node's word decides, asked
 *  anew; a term for what nobody opened and a ceiling for the whole keep the cache by themselves. */
export function CacheSection() {
  const [st, setSt] = useState(null);
  const [asking, setAsking] = useState(false);
  const [clearing, setClearing] = useState(false);
  const [word, setWord] = useState(null);
  const look = (ask) => invoke("home_files_state", { ask }).then(setSt).catch(() => {});
  useEffect(() => { look(true); }, []);
  if (!st) return null;
  const term = (days, limit) => invoke("cache_term", { days, limit }).then(() => look(false)).catch(() => {});
  const clear = () => {
    setAsking(false);
    setClearing(true);
    invoke("cache_clear").then((r) => setWord(fmt(t("Cleared from this computer: %lld files, %@. Your node keeps them."), r.files, size(r.bytes))))
      .catch(() => setWord(t("Your node did not answer. Nothing was cleared.")))
      .finally(() => { setClearing(false); look(true); });
  };
  const off = !st.bringing;
  return (
    <>
      <Section head={t("CACHE")} foot={st.bringing
        ? t("What your node holds leaves this computer. Each photo, video and file comes back from your node when you open it, here or on a new computer with your 24 words.")
        : t("Set up your node in Settings, Your node: what it holds can then be cleared from this computer and comes back when you open it.")}>
        {st.word?.files != null && <Row icon="server" color={GRAY} title={t("Kept on your node")} value={`${st.word.files} · ${size(st.word.bytes)}`} />}
        <button className="set-row" disabled={off || clearing} onClick={() => setAsking(true)} aria-label={t("Clear cache")}>
          <span className="row-icon" style={{ background: "#ff3b30" }}><Glyph name="trash" size={17} color="#fff" /></span>
          <span className="row-title">{t("Clear cache")}</span>
          {clearing && <span className="spinner small" />}
        </button>
        <label className={"set-row" + (off ? " off" : "")}>
          <span className="row-icon" style={{ background: BLUE }}><Glyph name="restore" size={17} color="#fff" /></span>
          <span className="row-title">{t("Keep media")}<span className="row-caption">{t("A photo, video or file your node holds leaves this computer when nobody has opened it for this long. It comes back from your node when you open it.")}</span></span>
          <select className="span-menu" aria-label={t("Keep media")} value={st.keepDays} disabled={off} onChange={(e) => term(Number(e.target.value), st.limitGB)}>
            {[[3, "3 days"], [7, "1 week"], [30, "1 month"], [0, "Forever"]].map(([d, w]) => <option key={d} value={d}>{t(w)}</option>)}
          </select>
        </label>
        <label className={"set-row" + (off ? " off" : "")}>
          <span className="row-icon" style={{ background: GRAY }}><Glyph name="server" size={17} color="#fff" /></span>
          <span className="row-title">{t("Maximum cache size")}<span className="row-caption">{t("Past this size the files opened longest ago leave this computer first, only those your node holds.")}</span></span>
          <select className="span-menu" aria-label={t("Maximum cache size")} value={st.limitGB} disabled={off} onChange={(e) => term(st.keepDays, Number(e.target.value))}>
            {[5, 16, 32].map((g) => <option key={g} value={g}>{size(g * 1073741824)}</option>)}
            <option value={0}>{t("No limit")}</option>
          </select>
        </label>
      </Section>
      {asking && (
        // iOS: a confirmationDialog with its title shown -- the platform's action sheet from below, as the chat's deletion
        <div className="sheet-shade" onClick={() => setAsking(false)}>
          <div className="action-sheet" onClick={(e) => e.stopPropagation()} role="alertdialog" aria-label={t("Clear the cache?")}>
            <div className="action-group">
              <div className="action-title"><b>{t("Clear the cache?")}</b>{t("Only what your node holds leaves this computer; what it does not hold stays.")}</div>
              <button className="action red" onClick={clear}>{t("Clear")}</button>
            </div>
            <button className="action cancel" onClick={() => setAsking(false)}>{t("Cancel")}</button>
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

/** YOUR NODE (iOS HomeNodeView, MontanaHomeNode.swift): the address, the node's word, the setting-up of a machine one owns, the two
 *  acts -- a copy now, the copy back -- and what the node names it can do. The machine joins from level 8 (iOS MTLevelAccess.ownNode);
 *  its copy comes back on every level. The keeper's word is the only word: what the page says is what the node answered. */
export function HomeNodePage({ onClose }) {
  const [s, setS] = useState(null);
  const [host, setHost] = useState("");
  const [road, setRoad] = useState({});
  const [word, setWord] = useState(null);
  const [login, setLogin] = useState("root");
  const [password, setPassword] = useState("");
  const [settingUp, setSettingUp] = useState(false);
  const [files, setFiles] = useState(null);   // the files on the node: the node's word on the book (iOS MTHomeKeep)
  const asked = useRef(0);
  const lookFiles = (ask) => invoke("home_files_state", { ask }).then(setFiles).catch(() => {});
  useEffect(() => { lookFiles(true); }, []);
  const look = () => {
    const n = ++asked.current;
    setS((x) => (x ? { ...x, asking: true } : x));
    invoke("home_node_state").then((r) => { if (n === asked.current) { setS(r); setHost((h) => h || r.host); } }).catch(() => {});
  };
  useEffect(() => {
    look();
    let stop = null, gone = false;
    listen("montana://home-node", (e) => setRoad((r) => ({ ...r, [e.payload.what]: e.payload.share }))).then((u) => { if (gone) u(); else stop = u; });
    return () => { gone = true; stop?.(); };
  }, []);
  if (!s) return <Page title={t("Your node")} onClose={onClose} back />;
  const commit = () => invoke("home_node_host", { host }).then((h) => { setHost(h); if (h !== s.host) look(); });
  const open = s.opens;
  const st = s.state || {};
  const holds = st.kind === "Held";
  const going = road.sealing != null || road.sending != null || road.fetching != null || road.restoring != null;
  const levelWord = open ? null : fmt(t("Opens at level %1$lld. Your level is %2$lld."), s.at, s.level);
  const sendNow = () => {
    commit();
    invoke("home_node_send").then((r) => { setWord(fmt(t("Taken by your node: %lld conversations, %lld records, %lld attachments."), r.chats, r.records, r.media)); look(); })
      .catch((e) => { setWord(spoken(String(e))); look(); });
  };
  // A MACHINE PUT UP FROM HERE (iOS setUp; the author's word 28.09: by the root login, the password and the address)
  const setUp = () => {
    if (!open) return;
    setSettingUp(true);
    invoke("home_node_setup", { host, login: login.trim() || "root", password })
      .then((h) => { setPassword(""); setHost(h); setWord(t("Your node is set up: its door stands at %@ and its certificate is pinned.").replace("%@", h)); look(); })
      .catch((e) => setWord(t("The set-up refused: %@").replace("%@", String(e))))
      .finally(() => setSettingUp(false));
  };
  const restore = () => {
    invoke("home_node_take_back").then((r) => setWord(fmt(t("Taken into this device: %lld conversations, %lld records, %lld attachments."), r.chats, r.records, r.media)))
      .catch((e) => setWord(spoken(String(e))));
  };
  const bar = (title, f) => (
    <div className="set-row node-bar" role="progressbar" aria-label={title} aria-valuenow={Math.round((f || 0) * 100)}>
      <span className="row-title">{title}</span><span className="row-value">{Math.round((f || 0) * 100)}%</span>
      <div className="node-track"><i style={{ width: `${Math.round((f || 0) * 100)}%` }} /></div>
    </div>
  );
  const stateRow = () => {
    if (s.asking) return <Row title={t("Asking your node…")}><span className="spinner small" /></Row>;
    if (st.kind === "None") return <Row title={t("Your node holds no copy")} />;
    if (st.kind === "Held") return <Row title={t("Held by your node")} value={`${st.moment} · ${size(st.bytes)}`} />;
    if (st.kind === "Refused") return <Row title={<span className="red">{t("Your node refused")}</span>} value={st.why} />;
    if (st.kind === "Silent") return <Row title={t("Your node did not answer")} value={st.why} />;
    return null;
  };
  return (
    <Page title={t("Your node")} onClose={onClose} back>
      <Section head={t("YOUR NODE")} foot={t("Your node is a machine you own: your backup, your space. Once a day, not over a cellular network, while Montana is open, a copy of the whole app goes there, sealed with the key your 24 words open; the words are not in it. On a new computer, enter the address and the words, and the copy comes back.")}>
        <div className="set-row">
          <span className="row-icon" style={{ background: GRAY }}><Glyph name="server" size={17} color="#fff" /></span>
          <input className="set-field node-host" placeholder={t("Address")} aria-label={t("Address")} value={host} spellCheck={false} autoCapitalize="off"
                 onChange={(e) => setHost(e.target.value)} onBlur={commit} onKeyDown={(e) => e.key === "Enter" && e.currentTarget.blur()} />
        </div>
        {stateRow()}
        {settingUp && <Row title={t("Setting up your node…")}><span className="spinner small" /></Row>}
        {road.sealing != null && bar(t("Sealing the copy for your node"), road.sealing)}
        {road.sending != null && bar(t("Sending to your node"), road.sending)}
        {road.fetching != null && bar(t("Downloading from your node"), road.fetching)}
        {road.restoring != null && bar(t("Restoring from your node"), road.restoring)}
      </Section>
      <Section foot={<>{t("Enter the address of a machine you own, its login and password: Montana puts its door on it and keeps only the digest of the certificate the machine makes for itself. The password is used once and kept nowhere.")}{levelWord && <><br /><br />{levelWord}</>}</>}>
        <div className="set-row">
          <span className="row-icon" style={{ background: GRAY }}><Glyph name="personCircle" size={17} color="#fff" /></span>
          <span className="row-title">{t("Login")}</span>
          <input className="set-field node-cred" placeholder={t("Login")} aria-label={t("Login")} value={login} spellCheck={false} onChange={(e) => setLogin(e.target.value)} />
        </div>
        <div className="set-row">
          <span className="row-icon" style={{ background: GRAY }}><Glyph name="key" size={17} color="#fff" /></span>
          <span className="row-title">{t("Password")}</span>
          <input className="set-field node-cred" type="password" placeholder={t("Password")} aria-label={t("Password")} value={password} onChange={(e) => setPassword(e.target.value)} />
        </div>
        <button className="set-row" disabled={!host || !password || settingUp || !open} onClick={setUp} aria-label={t("Set up your node")}>
          <span className="row-icon" style={{ background: BLUE }}><Glyph name="settings" size={17} color="#fff" /></span>
          <span className="row-title">{t("Set up your node")}</span>
        </button>
      </Section>
      <Section foot={levelWord}>
        <Toggle icon="restore" color={GREEN} title={t("Copies to your node")} on={s.switched && open} disabled={!open || !host}
                onChange={(v) => { commit(); invoke("home_node_switch", { on: v }).then(look); }}
                caption={t("Once a day, while Montana is open and on Wi-Fi only, a sealed copy of the whole app goes to your node. Off, nothing is sent and nothing is removed from the node.")} />
        <button className="set-row" disabled={!host || going || !open} onClick={sendNow} aria-label={t("Send a copy now")}>
          <span className="row-icon" style={{ background: GREEN }}><Glyph name="arrowUp" size={17} color="#fff" /></span>
          <span className="row-title">{t("Send a copy now")}</span>
        </button>
        <button className="set-row" disabled={!holds || going} onClick={restore} aria-label={t("Restore from your node")}>
          <span className="row-icon" style={{ background: ORANGE }}><Glyph name="download" size={17} color="#fff" /></span>
          <span className="row-title">{t("Restore from your node")}</span>
        </button>
      </Section>
      {/* THE FILES ON YOUR NODE (iOS 18.10): every attachment in sealed pieces, the node's word on what it holds, this computer's own
          count of what it is laying now */}
      <Section head={t("FILES ON YOUR NODE")} foot={t("Every photo, video, voice and file of your chats goes to your node in sealed pieces, not over a cellular network, while Montana is open. Data and Storage clears from this computer what your node holds; each comes back when you open it.")}>
        {files?.word?.files != null && <Row title={t("Files held by your node")} value={`${files.word.files} · ${size(files.word.bytes)}`} />}
        {files?.word?.silent && <Row title={t("Your node did not answer")} value={files.word.silent} />}
        {road.laying != null && bar(t("Laying your files on your node"), road.laying)}
        <button className="set-row" disabled={!host || road.laying != null || !open || !s.switched}
                onClick={() => invoke("home_files_keep").then(() => lookFiles(false)).catch(() => lookFiles(false))} aria-label={t("Keep files on your node now")}>
          <span className="row-icon" style={{ background: GREEN }}><Glyph name="server" size={17} color="#fff" /></span>
          <span className="row-title">{t("Keep files on your node now")}</span>
        </button>
      </Section>
      {s.caps?.length > 0 && (
        <Section head={t("WHAT YOUR NODE OFFERS")}>
          {CAPS.map(([id, w, g]) => (
            <div key={id} className="set-row" role="group" aria-label={`${t(w)}${s.caps.includes(id) ? " ✓" : ""}`}>
              <span className="row-icon" style={{ background: s.caps.includes(id) ? BLUE : GRAY }}><Glyph name={g} size={17} color="#fff" /></span>
              <span className="row-title">{t(w)}</span>
              <span style={{ opacity: s.caps.includes(id) ? 1 : 0 }}><Glyph name="tick" size={18} color="#fff" /></span>
            </div>
          ))}
        </Section>
      )}
      {word && (
        <div className="alert-shade" role="alertdialog" aria-label={t("Your node")}>
          <div className="alert">
            <b>{t("Your node")}</b>
            <p>{word}</p>
            <div className="alert-keys"><button className="bold" onClick={() => setWord(null)}>{t("OK")}</button></div>
          </div>
        </div>
      )}
    </Page>
  );
}
