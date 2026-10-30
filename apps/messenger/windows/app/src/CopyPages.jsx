import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { mtSize, t } from "./strings.js";
import { Page, Section, Toggle } from "./Settings.jsx";
import { Glyph } from "./TopBar.jsx";
import { useFile } from "./Media.jsx";

/** WHAT GOES INTO A COPY, AND THE PAGES WHERE A PERSON SEES IT AND CHOOSES (iOS MontanaBackupPlan.swift: CopyChatsPage,
 *  CopyKindsPage, CopyFilesPage, CopyFileView; the author, 23.09 01:31). Everything goes by default; the plan is what the person
 *  left out -- a conversation, a kind, one file -- kept on this computer, and every copy obeys it. The numbers are counted from
 *  what this computer holds. */

const BLUE = "#0a84ff", PURPLE = "#bf5af2", ORANGE = "#ff9500", GRAY = "#8e8e93", ACCENT = "#0a84ff";
/** iOS CopyKindsPage.face: each kind's title, glyph and colour. */
const KINDS = [["photo", "Photos", "photo", BLUE], ["video", "Videos", "video", PURPLE], ["voice", "Voice messages", "mic", ORANGE], ["file", "Files", "doc", GRAY]];
const kindFace = (k) => KINDS.find((x) => x[0] === k) || KINDS[3];

const fill = (s, ...v) => { let i = 0; return s.replace(/%(?:(\d+)\$)?(?:lld|@)/g, (_, n) => String(v[n ? n - 1 : i++])); };
const takesChat = (plan, r) => !plan.skipChats.includes(r);
const takesKind = (plan, k) => !plan.skipKinds.includes(k);
/** A file goes when its conversation, its kind and the file itself all go (iOS Scope.takes(file:)); a file no letter names is in no
 *  copy of this computer (the copy carries the letters' files). */
const takesFile = (plan, f) => !!f.chat && takesChat(plan, f.chat) && takesKind(plan, f.kind) && !plan.skipFiles.includes(f.name);

/** The pages from Data and Storage, one over another: `start` is «chats» or «kinds». */
export function CopyStack({ start, onClose }) {
  const [inv, setInv] = useState(null);
  const [stack, setStack] = useState([start]);
  const read = () => invoke("copy_pages").then((v) => setInv({ ...v, plan: { skipChats: [], skipKinds: [], skipFiles: [], ...v.plan } })).catch(() => {});
  useEffect(() => { read(); }, []);
  // the plan's last write: Data and Storage, standing under these pages, counts again the moment they close (as iOS on appear),
  // so the last page waits for the write to land -- a count taken before it would show the plan as it was (26.10.2026, datapage)
  const written = useRef(Promise.resolve());
  const plan = (next) => { setInv((x) => ({ ...x, plan: next })); written.current = invoke("copy_plan_set", { plan: next }).catch(() => {}); };
  const push = (p) => setStack((s) => [...s, p]);
  const pop = () => setStack((s) => (s.length > 1 ? s.slice(0, -1) : (written.current.then(onClose), s)));
  const top = stack[stack.length - 1];
  if (!inv) return <Page title={t(start === "chats" ? "Conversations" : "Attachments")} onClose={onClose} back />;
  if (top === "chats") return <CopyChatsPage inv={inv} plan={plan} onClose={pop} />;
  if (top === "kinds") return <CopyKindsPage inv={inv} plan={plan} onClose={pop} onKind={(k) => push(`files:${k}`)} />;
  if (top.startsWith("files:")) return <CopyFilesPage inv={inv} kind={top.slice(6)} plan={plan} onClose={pop} onFile={(n) => push(`file:${n}`)} reread={read} />;
  const f = inv.files.find((x) => x.name === top.slice(5));
  return <CopyFileView inv={inv} f={f} onClose={pop} reread={read} />;
}

/** THE CONVERSATIONS OF A COPY (iOS CopyChatsPage): every one this computer holds, its letters and the weight of its attachments;
 *  the whole row answers the finger, the mark says what the copy takes. */
function CopyChatsPage({ inv, plan, onClose }) {
  const flip = (r) => { const s = inv.plan.skipChats; plan({ ...inv.plan, skipChats: s.includes(r) ? s.filter((x) => x !== r) : [...s, r] }); };
  return (
    <Page title={t("Conversations")} onClose={onClose} back>
      <Section foot={t("A conversation left out is not read at all: none of its letters, names, faces or attachments go into the copy.")}>
        {inv.convs.map((c) => (
          <button key={c.id} className="set-row copy-chat" onClick={() => flip(c.id)} aria-pressed={takesChat(inv.plan, c.id)} aria-label={c.title}>
            <span className="copy-face" aria-hidden="true">{(c.title || "?").trim().charAt(0).toUpperCase()}</span>
            <span className="row-title">{c.title}<span className="row-caption">{fill(t("%lld letters · %@"), c.letters, mtSize(c.bytes))}</span></span>
            <span className="copy-mark" style={{ opacity: takesChat(inv.plan, c.id) ? 1 : 0 }}><Glyph name="tick" size={18} color={ACCENT} /></span>
          </button>
        ))}
      </Section>
    </Page>
  );
}

/** THE ATTACHMENTS OF A COPY (iOS CopyKindsPage): by kind, each with its count and weight on this computer; a row opens the kind's
 *  own files, its mark says whether the copy takes the kind. */
function CopyKindsPage({ inv, onClose, onKind }) {
  return (
    <Page title={t("Attachments")} onClose={onClose} back>
      <Section foot={inv.missing > 0 ? fill(t("Attachments this computer never downloaded are not on it and cannot go into the copy: %lld."), inv.missing)
                                     : t("Every attachment the letters name is on this computer.")}>
        {KINDS.map(([k, title, icon, color]) => {
          const files = inv.files.filter((f) => f.kind === k);
          return (
            <button key={k} className="set-row" onClick={() => onKind(k)} aria-label={t(title)}>
              <span className="row-icon" style={{ background: color }}><Glyph name={icon} size={17} color="#fff" /></span>
              <span className="row-title">{t(title)}</span>
              <span className="row-value">{`${files.length} · ${mtSize(files.reduce((a, f) => a + f.bytes, 0))}`}</span>
              <span className="copy-mark" style={{ opacity: takesKind(inv.plan, k) ? 1 : 0 }}><Glyph name="tick" size={18} color={ACCENT} /></span>
              <span className="row-chevron"><Glyph name="chevronRight" size={14} color="rgba(235,235,245,0.3)" /></span>
            </button>
          );
        })}
      </Section>
    </Page>
  );
}

/** ONE KIND'S FILES (iOS CopyFilesPage; the author, 23.09 and 18.10.2026 10:2x MSK: «a convenient mass way to select everything
 *  and delete, for example all videos»): heaviest first; the round mark leaves a file out of the copy or puts it back; «Select»
 *  chooses many -- all by one glyph -- and the chosen leave this computer by one question, on the node's word. */
function CopyFilesPage({ inv, kind, plan, onClose, onFile, reread }) {
  const [choosing, setChoosing] = useState(false);
  const [chosen, setChosen] = useState(new Set());
  const [asking, setAsking] = useState(false);
  const [stayed, setStayed] = useState(0);
  const files = inv.files.filter((f) => f.kind === kind).sort((a, b) => b.bytes - a.bytes || a.name.localeCompare(b.name));
  const kept = files.filter((f) => takesFile(inv.plan, f));
  const whose = (f) => inv.convs.find((c) => c.id === f.chat)?.title;
  const free = (f) => !!f.chat && takesKind(inv.plan, kind) && takesChat(inv.plan, f.chat);
  const flip = (n) => { const s = inv.plan.skipFiles; plan({ ...inv.plan, skipFiles: s.includes(n) ? s.filter((x) => x !== n) : [...s, n] }); };
  const inCopy = (on) => plan({ ...inv.plan, skipKinds: on ? inv.plan.skipKinds.filter((k) => k !== kind) : [...inv.plan.skipKinds.filter((k) => k !== kind), kind] });
  const pick = (n) => setChosen((s) => { const x = new Set(s); if (x.has(n)) x.delete(n); else x.add(n); return x; });
  const all = files.length > 0 && chosen.size === files.length;
  const remove = () => {
    const many = [...chosen];
    setAsking(false); setChosen(new Set()); setChoosing(false);
    invoke("copy_remove", { names: many }).then((gone) => {
      plan({ ...inv.plan, skipFiles: inv.plan.skipFiles.filter((n) => !gone.includes(n)) });
      setStayed(many.length - gone.length);
      reread();
    }).catch(() => setStayed(many.length));
  };
  const [title] = kindFace(kind).slice(1);
  const right = choosing ? (
    <>
      <button className="glass-mark" onClick={() => setChosen(all ? new Set() : new Set(files.map((f) => f.name)))} aria-label={t("Select All")}>
        <Glyph name="checkCircle" size={18} color={all ? ACCENT : "rgb(204,204,204)"} /></button>
      <button className="glass-mark" disabled={!chosen.size} onClick={() => setAsking(true)} aria-label={t("Delete")}>
        <Glyph name="trash" size={18} color="var(--bar-glyph)" /></button>
      <button className="glass-mark" onClick={() => { setChoosing(false); setChosen(new Set()); }} aria-label={t("Done")}>
        <Glyph name="close" size={18} color="var(--bar-glyph)" /></button>
    </>
  ) : (
    <button className="glass-mark" disabled={!files.length} onClick={() => setChoosing(true)} aria-label={t("Select")}>
      <Glyph name="list" size={18} color="var(--bar-glyph)" /></button>
  );
  return (
    <Page title={t(title)} onClose={onClose} back right={right}>
      <Section foot={fill(t("In the copy: %lld of %lld · %@"), kept.length, files.length, mtSize(kept.reduce((a, f) => a + f.bytes, 0)))}>
        <Toggle title={t("In the copy")} on={takesKind(inv.plan, kind)} onChange={inCopy} />
      </Section>
      <Section foot={t("The round mark leaves a file out of the copy or puts it back; «Select» removes files from this computer.")}>
        {files.map((f) => {
          const takes = takesFile(inv.plan, f);
          const mark = choosing ? chosen.has(f.name) : takes;
          return (
            <div key={f.name} className="set-row copy-file">
              <button className="copy-round" disabled={!choosing && !free(f)} onClick={() => (choosing ? pick(f.name) : flip(f.name))}
                      aria-pressed={mark} aria-label={choosing ? `${t("Select")}: ${whose(f) || f.name}` : `${t(takes ? "Leave out of the copy" : "Put back into the copy")}: ${whose(f) || f.name}`}>
                <span className={"copy-ring" + (mark ? " on" : "") + (choosing ? " red" : "")}>{mark && <Glyph name="tick" size={14} color="#fff" />}</span>
              </button>
              <button className="copy-open" onClick={() => onFile(f.name)} aria-label={whose(f) || t("No letter on this computer names it")}>
                <span className="copy-icon"><Glyph name={kindFace(f.kind)[2]} size={20} color="#fff" />{f.e && <small>{String(f.e).toUpperCase()}</small>}</span>
                <span className="row-title">
                  {whose(f) ? <span className="copy-who">{whose(f)}</span> : <span className="copy-who none">{t("No letter on this computer names it")}</span>}
                  <span className="row-caption">{mtSize(f.bytes)}</span>
                </span>
                <span className="row-chevron"><Glyph name="chevronRight" size={14} color="rgba(235,235,245,0.3)" /></span>
              </button>
            </div>
          );
        })}
      </Section>
      {asking && <RemoveSheet title={fill(t("Remove %lld files from this computer?"), chosen.size)}
                              message={t("Your node keeps them, and each comes back when you open it. The letters stay. A file your node does not hold yet stays on this computer.")}
                              onRemove={remove} onCancel={() => setAsking(false)} />}
      {stayed > 0 && (
        <div className="alert-shade" role="alertdialog" aria-label={t("Cache")}>
          <div className="alert">
            <b>{t("Cache")}</b>
            <p>{fill(t("Your node does not hold %lld of the chosen files yet: they stay on this computer."), stayed)}</p>
            <div className="alert-keys"><button className="bold" onClick={() => setStayed(0)}>{t("OK")}</button></div>
          </div>
        </div>
      )}
    </Page>
  );
}

/** The question before a file leaves this computer (iOS confirmationDialog with its title): the platform's action sheet. */
function RemoveSheet({ title, message, onRemove, onCancel }) {
  return (
    <div className="sheet-shade" onClick={onCancel}>
      <div className="action-sheet" onClick={(e) => e.stopPropagation()} role="alertdialog" aria-label={title}>
        <div className="action-group">
          <div className="action-title"><b>{title}</b>{message}</div>
          <button className="action red" onClick={onRemove}>{t("Remove from this computer")}</button>
        </div>
        <button className="action cancel" onClick={onCancel}>{t("Cancel")}</button>
      </div>
    </div>
  );
}

/** ONE FILE, OPENED INSIDE THE PAGE (iOS CopyFileView; the author, 23.09 02:40: «it opens within this page, and closing returns to
 *  the previous one»): the picture, the film, the voice drawn here; a file of another kind opens in its program from here. The
 *  bin takes it off this computer, on the node's word, and returns. */
function CopyFileView({ inv, f, onClose, reread }) {
  const [asking, setAsking] = useState(false);
  const [stayed, setStayed] = useState(false);
  const url = useFile(f?.mid, !!f?.mid, f?.e, (f?.bytes || 0) > 200 * 1024 * 1024);   // a big one by its ranges, never whole
  const title = (f && inv.convs.find((c) => c.id === f.chat)?.title) || t(kindFace(f?.kind)[1]);
  const remove = () => {
    setAsking(false);
    invoke("copy_remove", { names: [f.name] }).then((gone) => { reread(); if (gone.length) onClose(); else setStayed(true); }).catch(() => setStayed(true));
  };
  const right = f?.mid ? <button className="glass-mark" onClick={() => setAsking(true)} aria-label={t("Remove from this computer")}><Glyph name="trash" size={18} color="var(--bar-glyph)" /></button> : null;
  return (
    <Page title={title} onClose={onClose} back right={right}>
      <div className="copy-view">
        {!f?.mid ? <div className="copy-none">{t("The file is not on this computer. Ask the sender to send it again.")}</div>
          : !url ? <span className="spinner" />
          : f.kind === "photo" ? <img src={url} alt="" />
          : f.kind === "video" ? <video src={url} controls />
          : f.kind === "voice" ? <audio src={url} controls />
          : <button className="link-button" onClick={() => invoke("media_open", { chat: f.chat, mid: f.mid })}>{t("Open")}</button>}
      </div>
      {asking && <RemoveSheet title={t("Remove from this computer?")} message={t("Your node keeps it, and it comes back when you open it. The letter stays.")}
                              onRemove={remove} onCancel={() => setAsking(false)} />}
      {stayed && (
        <div className="alert-shade" role="alertdialog" aria-label={t("Cache")}>
          <div className="alert">
            <b>{t("Cache")}</b>
            <p>{fill(t("Your node does not hold %lld of the chosen files yet: they stay on this computer."), 1)}</p>
            <div className="alert-keys"><button className="bold" onClick={() => setStayed(false)}>{t("OK")}</button></div>
          </div>
        </div>
      )}
    </Page>
  );
}
