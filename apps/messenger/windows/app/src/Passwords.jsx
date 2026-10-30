import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { ForwardSheet } from "./Conversation.jsx";

const KINDS = [["login", "Sign-in", "key"], ["code", "One-time code", "lock"], ["note", "Note", "textDoc"]];
const blank = { id: "", kind: "login", title: "", site: "", login: "", password: "", otp: "", note: "", at: 0 };

/** A one-time code standing now, and the seconds it still stands (iOS MTCodeLive). */
function CodeLive({ otp }) {
  const [c, setC] = useState(null);
  useEffect(() => {
    let live = true;
    const look = () => invoke("password_code", { otp }).then((r) => live && setC(r)).catch(() => {});
    look();
    const id = setInterval(look, 1000);
    return () => { live = false; clearInterval(id); };
  }, [otp]);
  if (!c) return <span className="row-caption">—</span>;
  return <span className="pw-code" aria-label={`${t("One-time code")}: ${c[0]}`}>{c[0].replace(/(\d{3})(?=\d)/g, "$1 ")}<small>{c[1]}</small></span>;
}

/** One field of a secret, its value hidden where it is a password, copied out of the clipboard's history for ninety seconds. */
function Field({ label, value, hide, onSaid }) {
  const [shown, setShown] = useState(!hide);
  if (!value) return null;
  return (
    <div className="pw-field">
      <span className="row-caption">{t(label)}</span>
      <span className="pw-value">{shown ? value : "••••••••••"}</span>
      {hide && <button onClick={() => setShown(!shown)} aria-label={t(shown ? "Hide" : "Show")}>{t(shown ? "Hide" : "Show")}</button>}
      <button onClick={() => invoke("password_copy", { value }).then(() => onSaid(t("Copied")))} aria-label={`${t("Copy")}: ${t(label)}`}>{t("Copy")}</button>
    </div>
  );
}

/** THE PASSWORDS PAGE (iOS MTPasswordsPage): locked until Windows Hello says it is the person; then the secrets by kind, searched,
 *  each with its page; «Новый» writes one. */
export default function PasswordsPane() {
  const [items, setItems] = useState(null);
  const [why, setWhy] = useState(null);
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(null);      // the item shown
  const [editing, setEditing] = useState(null);
  const [sharing, setSharing] = useState(null);
  const [said, setSaid] = useState(null);
  const unlock = () => { setWhy(null); invoke("passwords_open").then(setItems).catch((e) => setWhy(String(e))); };
  useEffect(() => { unlock(); return () => { invoke("passwords_lock").catch(() => {}); }; }, []);
  const say = (s) => { setSaid(s); setTimeout(() => setSaid(null), 2500); };

  if (!items) {
    return (
      <div className="pw-pane locked">
        <Glyph name="lock" size={44} color="rgba(235,235,245,0.6)" />
        <div className="row-caption">{why === "notset"
          ? t("Set up Windows Hello: without it the passwords cannot be protected.")
          : t("Your passwords unlock with Windows Hello.")}</div>
        {why === "refused" && <div className="problem" role="status">{t("The passwords did not open.")}</div>}
        {why !== "notset" && <button className="pw-unlock" onClick={unlock}>{t("Unlock")}</button>}
      </div>
    );
  }
  if (editing) {
    const e = editing;
    const set = (k, v) => setEditing({ ...e, [k]: v });
    return (
      <div className="pw-pane">
        <div className="pw-head">
          <button onClick={() => setEditing(null)}>{t("Cancel")}</button><b>{t(e.id ? "Edit" : "New")}</b>
          <button disabled={!e.title.trim()} onClick={() => invoke("passwords_save", { item: e }).then((r) => { setItems(r); setEditing(null); }).catch(() => say(t("Not saved")))}>{t("Done")}</button>
        </div>
        <div className="pw-kinds">{KINDS.map(([k, label]) => <button key={k} className={e.kind === k ? "on" : ""} onClick={() => set("kind", k)}>{t(label)}</button>)}</div>
        {[["title", "Title"], ["site", "Site"], ["login", "Login"]].map(([k, l]) => (
          <input key={k} className="set-field" placeholder={t(l)} aria-label={t(l)} value={e[k]} onChange={(x) => set(k, x.target.value)} />
        ))}
        {e.kind === "login" && (
          <div className="pw-row">
            <input className="set-field" placeholder={t("Password")} aria-label={t("Password")} value={e.password} onChange={(x) => set("password", x.target.value)} />
            <button onClick={() => invoke("password_fresh").then((v) => set("password", v))}>{t("Generate password")}</button>
          </div>
        )}
        {e.kind !== "note" && <input className="set-field" placeholder={t("Key or otpauth:// link")} aria-label={t("Key or otpauth:// link")} value={e.otp} onChange={(x) => set("otp", x.target.value)} />}
        <textarea className="set-field" rows={4} placeholder={t("Note")} aria-label={t("Note")} value={e.note} onChange={(x) => set("note", x.target.value)} />
      </div>
    );
  }
  if (open) {
    const e = items.find((x) => x.id === open);
    if (!e) { setOpen(null); return null; }
    return (
      <div className="pw-pane">
        <div className="pw-head">
          <button onClick={() => setOpen(null)}>{t("Back")}</button><b>{e.title}</b>
          <button onClick={() => setEditing(e)}>{t("Edit")}</button>
        </div>
        <Field label="Site" value={e.site} onSaid={say} />
        <Field label="Login" value={e.login} onSaid={say} />
        <Field label="Password" value={e.password} hide onSaid={say} />
        {e.otp && <div className="pw-field"><span className="row-caption">{t("One-time code")}</span><CodeLive otp={e.otp} /></div>}
        <Field label="Note" value={e.note} onSaid={say} />
        <div className="pw-deeds">
          <button onClick={() => setSharing(e.id)}>{t("Share")}</button>
          <button className="red" onClick={() => invoke("passwords_remove", { id: e.id }).then((r) => { setItems(r); setOpen(null); })}>{t("Delete")}</button>
        </div>
        {said && <div className="row-caption" role="status">{said}</div>}
        {sharing && <ForwardSheet title={t("Share")} onClose={() => setSharing(null)}
                                  onPick={(to) => { const id = sharing; setSharing(null); invoke("secret_send", { chat: to, id }).then(() => say(t("Sent"))).catch(() => say(t("Not sent"))); }} />}
      </div>
    );
  }
  const shown = items.filter((e) => !q.trim() || [e.title, e.site, e.login, e.note].some((f) => f.toLowerCase().includes(q.trim().toLowerCase())));
  return (
    <div className="pw-pane">
      <div className="pw-head"><span /><b>{t("Passwords")}</b><button onClick={() => setEditing({ ...blank })} aria-label={t("New")}>＋ {t("New")}</button></div>
      <input className="set-field" type="search" placeholder={t("Search")} aria-label={t("Search")} value={q} onChange={(x) => setQ(x.target.value)} />
      {!items.length && <div className="row-caption">{t("No passwords yet")}</div>}
      {KINDS.map(([k, label, glyph]) => {
        const rows = shown.filter((e) => e.kind === k);
        if (!rows.length) return null;
        return (
          <div key={k} className="pw-section">
            <div className="sect-head">{t(label)}</div>
            {rows.map((e) => (
              <button key={e.id} className="set-row" onClick={() => setOpen(e.id)} aria-label={e.title}>
                <Glyph name={glyph} size={18} color="#fff" /><span className="row-title">{e.title}<span className="row-caption">{e.login || e.site}</span></span>
              </button>
            ))}
          </div>
        );
      })}
      {said && <div className="row-caption" role="status">{said}</div>}
    </div>
  );
}
