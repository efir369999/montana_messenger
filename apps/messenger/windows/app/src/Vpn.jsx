import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { mtSize, t } from "./strings.js";
import { Section } from "./Settings.jsx";
import { Glyph } from "./TopBar.jsx";

/** THE VPN WALL (iOS NetworkTabView / MontanaVPNStore, MontanaVPN.swift): the person's plans and the servers each brought, the servers
 *  added by hand, a row's menu (rename, the link, the engine's JSON, delete) and a plan's (update, fold, delete). The page's search
 *  narrows the servers by name, host, protocol, transport and wrapper. The tunnel itself waits for the engine (Rust: vpn.rs). */

/** What a panel counted, as iOS says it (MontanaNetworkView.mtBytes: .byteCount(style: .binary)). */
const bytes = (n) => (n == null ? "" : mtSize(n, true));

function Row({ s, onDo, menu, setMenu }) {
  const open = menu === s.id;
  const [naming, setNaming] = useState(null);   // the row's new name being typed (iOS: the alert of «Rename»)
  if (naming != null) {
    const done = () => { onDo("rename", s.id, naming); setNaming(null); };
    return (
      <div className="set-row">
        <input className="set-field" autoFocus aria-label={t("Rename")} value={naming} maxLength={64}
               onChange={(e) => setNaming(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") done(); if (e.key === "Escape") { e.preventDefault(); setNaming(null); } }} />
        <button className="link-button" onClick={done}>{t("Done")}</button>
      </div>
    );
  }
  return (
    <div className="set-row" role="group" aria-label={s.name}>
      <span className="row-title">{s.name}<br /><span className="vpn-row-sub">
        {s.proto === "unsupported" ? `${s.scheme || "?"} · ${t("The engine this protocol needs is not in Montana")}` : `${s.proto} · ${s.network} · ${s.security} · ${s.host}:${s.port}`}
      </span></span>
      <button className="glass-mark" onClick={() => setMenu(open ? null : s.id)} aria-label={`${t("More")}: ${s.name}`}><Glyph name="more" size={18} color="#fff" /></button>
      {open && (
        <div className="post-menu" role="menu">
          <button role="menuitem" onClick={() => { setNaming(s.name); setMenu(null); }}>{t("Rename")}</button>
          <button role="menuitem" onClick={() => { onDo("link", s.id); setMenu(null); }}>{t("Copy link")}</button>
          {s.proto !== "unsupported" && <button role="menuitem" onClick={() => { onDo("json", s.id); setMenu(null); }}>{t("Copy JSON")}</button>}
          <button role="menuitem" className="red" onClick={() => { onDo("remove", s.id); setMenu(null); }}>{t("Delete")}</button>
        </div>
      )}
    </div>
  );
}

export default function VpnPane({ query = "" }) {
  const [st, setSt] = useState(null);
  const [text, setText] = useState("");
  const [said, setSaid] = useState(null);
  const [busy, setBusy] = useState(false);
  const [menu, setMenu] = useState(null);
  const read = () => invoke("vpn_state").then(setSt).catch(() => {});
  useEffect(() => { read(); }, []);
  const add = async () => {
    if (!text.trim() || busy) return;
    setBusy(true); setSaid(null);
    try {
      const out = await invoke("vpn_add", { text });
      const [kind, n] = out.split(":");
      setSaid(kind === "plan" ? t("The plan brought %@ servers").replace("%@", n) : t("Servers added: %@").replace("%@", n));
      setText("");
    } catch (e) {
      setSaid(e === "none" ? t("No server link in it") : t("The plan did not answer: %@").replace("%@", String(e)));
    }
    setBusy(false); read();
  };
  const act = async (what, id, name) => {
    try {
      const out = await invoke("vpn_do", { what, id, name: name ?? null });
      if (out === "copied") setSaid(t("Copied"));
    } catch (e) { setSaid(String(e)); }
    read();
  };
  if (!st) return null;
  const w = query.trim().toLowerCase();
  const matches = (s) => !w || [s.name, s.host, s.proto, s.network, s.security].some((x) => (x || "").toLowerCase().includes(w));
  const manual = st.servers.filter((s) => !s.plan && matches(s));
  return (
    <div className="vpn-pane" aria-label={t("VPN wall")}>
      <div className="wall-head">{t("VPN wall")}</div>
      {/* THE POWER (iOS MontanaVPNPowerButton): the tunnel needs the engine, which waits for the owner on Windows */}
      <button className="vpn-power" disabled aria-label={t("Connect")}><Glyph name="globe" size={56} color="currentColor" /></button>
      <div className="post-note" role="note">{t("On Windows the tunnel needs the Xray engine and a TUN driver: a program of another maker and the administrator's rights. Waiting for the owner's decision; the servers and plans are kept and checked here.")}</div>
      <Section head={t("Add a server or a plan")}>
        <textarea className="set-field" rows={3} placeholder={t("A server's link (vless, vmess, trojan, ss, hysteria2, wireguard, socks) or a plan's link")}
                  aria-label={t("Add a server or a plan")} value={text} onChange={(e) => setText(e.target.value)} />
        <button className="set-row accent" onClick={add} disabled={busy || !text.trim()}>{busy && <span className="spinner" />}<span className="row-title">{t("Add")}</span></button>
        {said && <div className="post-note" role="status">{said}</div>}
      </Section>
      {st.plans.map((p) => {
        const rows = st.servers.filter((s) => s.plan === p.url && matches(s));
        if (w && !rows.length && !p.title.toLowerCase().includes(w)) return null;
        const used = (p.upload || 0) + (p.download || 0);
        return (
          <Section key={p.url} head={
            <span className="vpn-plan-head">
              <button className="link-button" onClick={() => act("plan-fold", p.url)} aria-label={p.title} aria-expanded={p.folded !== true}>{p.title}</button>
              <button className="link-button" onClick={() => act("plan-reload", p.url)} aria-label={`${t("Update")}: ${p.title}`}>{t("Update")}</button>
              <button className="link-button red" onClick={() => act("plan-remove", p.url)} aria-label={`${t("Delete")}: ${p.title}`}>{t("Delete")}</button>
            </span>
          } foot={[t("Servers: %@").replace("%@", p.count), p.total ? t("Used %@ of %@").replace("%@", bytes(used)).replace("%@", bytes(p.total)) : used ? t("Used %@").replace("%@", bytes(used)) : null,
                   p.expire ? t("Expires %@").replace("%@", new Date(p.expire * 1000).toLocaleDateString()) : null, p.lastError].filter(Boolean).join(" · ")}>
            {(p.folded !== true || w) && rows.map((s) => <Row key={s.id} s={s} onDo={act} menu={menu} setMenu={setMenu} />)}
          </Section>
        );
      })}
      {manual.length > 0 && (
        <Section head={t("Added by hand")}>
          {manual.map((s) => <Row key={s.id} s={s} onDo={act} menu={menu} setMenu={setMenu} />)}
        </Section>
      )}
      {!st.servers.length && !st.plans.length && <div className="post-note">{t("No servers yet")}</div>}
    </div>
  );
}

/** THE P2P WALL (iOS NetworkTabView's P2P tab, the author's word 23.09: «the tab is the nodes»): how many nodes this computer
 *  reaches now, and who -- each machine of the network with its doors under it, every door with its answer: open (and its
 *  time), spare (its machine held by a faster door), lost, no answer. Asked again by «Обновить» and each half-minute. */
export function P2pPane() {
  const [nodes, setNodes] = useState(null);
  const [busy, setBusy] = useState(false);
  const read = () => { setBusy(true); invoke("p2p_wall").then(setNodes).catch(() => setNodes([])).finally(() => setBusy(false)); };
  useEffect(() => { read(); const id = setInterval(read, 30000); return () => clearInterval(id); }, []);
  const word = { open: "open", spare: "spare", lost: "lost", silent: "no answer" };
  const held = (nodes || []).filter((m) => m.held).length;
  return (
    <div className="vpn-pane" aria-label={t("P2P wall")}>
      <div className="wall-head">{t("P2P wall")}</div>
      <Section head={`${t("Reachable nodes")} (${nodes ? held : "…"})`}>
        {(nodes || []).map((m) => (
          <div key={m.id}>
            <div className="set-row" role="group" aria-label={`${t("node")} ${m.id}: ${t(m.held ? "held" : "lost")}`}>
              <Glyph name="globe" size={22} color="#fff" />
              <span className="row-title">{t("node")} {m.id}<br /><span className={"vpn-row-sub " + (m.held ? "ok" : "bad")}>{t(m.held ? "held" : "lost")}</span></span>
            </div>
            {m.doors.map((d) => (
              <div key={d.label} className="set-row p2p-door" role="group" aria-label={`${d.label}: ${t(word[d.state])}${d.ms != null ? ` · ${d.ms} ms` : ""}`}>
                <span className="row-title">{d.label}{d.ms != null ? `  ·  ${d.ms} ms` : ""}<br />
                  <span className={"vpn-row-sub " + (d.state === "open" || d.state === "spare" ? "ok" : d.state === "lost" ? "warn" : "bad")}>{t(word[d.state])}</span></span>
              </div>
            ))}
          </div>
        ))}
      </Section>
      <button className="set-row accent" onClick={read} disabled={busy}>{busy && <span className="spinner" />}<span className="row-title">{t("Update")}</span></button>
    </div>
  );
}
