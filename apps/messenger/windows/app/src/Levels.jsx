import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Page, Section } from "./Settings.jsx";

const fmt = (s, ...v) => v.reduce((x, n, i) => x.replace(`%${i + 1}$lld`, n).replace("%lld", n), s);

/** ACCESS BY LEVEL (iOS MTLevelAccessPage; the author's words 16.10.2026: «the gamification of access to Montana's functions»): the
 *  person's Global Level and the fabric of time beside it, then under each level the functions it opens -- switches the person moves
 *  once their level reaches it, each with its contract under it. Below its level a switch stands off. */
export function LevelsPage({ onClose }) {
  const [s, setS] = useState(null);
  const look = () => invoke("levels_state").then(setS).catch(() => {});
  useEffect(() => { look(); }, []);
  if (!s) return <Page title={t("Access by level")} onClose={onClose} back />;
  const set = (what, on) => invoke("levels_set", { what, on }).then(look);
  const toggle = (k, title, foot) => {
    const f = s[k], on = f.open && f.on;
    return (
      <label className={"set-row toggle-row" + (f.open ? "" : " off")} aria-label={title}>
        <span className="row-title">{title}<span className="row-caption">{foot}</span></span>
        <input type="checkbox" role="switch" checked={on} disabled={!f.open} aria-label={title}
               onChange={(e) => {
                 const v = e.target.checked;
                 if (k === "record" && v && !f.consent && !window.confirm(t("Audio and video are saved on this computer. For a one-to-one call, the caller sends the recording to the chat, or the one who answered when the caller does not record. Room participants send their own recordings. Participants are notified. You can turn this off in Settings, Access by level, at any time."))) return;
                 if (k === "record" && v) invoke("levels_set", { what: "consent", on: true });
                 set(k, v);
               }} />
      </label>
    );
  };
  const opens = (f) => (f.open ? null : fmt(t("Opens at level %1$lld. Your level is %2$lld."), f.at, s.level));
  return (
    <Page title={t("Access by level")} onClose={onClose} back>
      <Section foot={t("Your level is the lowest of three: your time in Montana, the coins you hold and the Fabric of Time, the people you write to and call regularly in the last two weeks, weighed by the levels their own time and wallet give them. Each level opens new functions of Montana.")}>
        <div className="set-row" role="group" aria-label={fmt(t("Global level %lld"), s.level)}><span className="row-title">{fmt(t("Global level %lld"), s.level)}</span></div>
        <div className="set-row" role="group" aria-label={`${t("Fabric of Time")}: ${s.fabric?.level ?? "—"}`}>
          <span className="row-title">{t("Fabric of Time")}{s.fabric?.graceDays != null && <span className="row-caption">{t("Days until the first count: %@").replace("%@", s.fabric.graceDays)}</span>}</span>
          <span className="row-value mono">{s.fabric?.level ?? "—"}</span>
        </div>
      </Section>
      <Section head={fmt(t("Level %lld"), s.keep.at)} foot={opens(s.keep)}>
        {toggle("keep", t("Forbid deletion on my computer"), t("A message your correspondent deletes for everyone stays on this computer, and their device is told so."))}
        {toggle("record", t("Record calls"), t("Calls are recorded by themselves on this computer and sent to the call's chat after your first consent. While this is off, a correspondent whose level is not above yours cannot record your calls; one with a higher level records on their side only. The record button on the call screen works on every level unless the correspondent's switch holds."))}
      </Section>
      <Section head={fmt(t("Level %lld"), s.node.at)} foot={opens(s.node)}>
        <div className={"set-row" + (s.node.open ? "" : " off")} role="group" aria-label={t("Your node")}>
          <span className="row-title">{t("Your node")}<span className="row-caption">{t("Connect a machine you own to the Montana network through this app: it is set up from here and copies of the whole computer go to it. Taking your copy back is open on every level.")}</span></span>
        </div>
      </Section>
    </Page>
  );
}
