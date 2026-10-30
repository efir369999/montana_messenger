import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { chatName } from "./Chats.jsx";
import { Page, Section, Toggle } from "./Settings.jsx";

/** THE BLOCK'S QUESTION (iOS ContentView 4546-4558): what blocking does, said before it is done. */
export function BlockSheet({ name, onBlock, onClose }) {
  return (
    <div className="sheet-shade" onClick={onClose}>
      <div className="action-sheet" onClick={(e) => e.stopPropagation()} role="alertdialog">
        <div className="action-group">
          <div className="action-title">
            <b>{t("Block this person?")}</b><br />
            {t("You will not receive messages, calls, typing or presence from this person. They will not see your photo or when you were online.")}
          </div>
          <button className="action red" onClick={onBlock}>{t("Block contact")}</button>
        </div>
        <button className="action cancel" onClick={onClose}>{t("Cancel")}</button>
      </div>
    </div>
  );
}

const REASONS = [["spam", "Spam"], ["abuse", "Harassment or threats"], ["hate", "Hate speech"], ["illegal", "Illegal content"], ["other", "Other"]];

/** A REPORT (iOS MontanaSafety 136-221): the reason, the letter if one, «also block» on by default; it goes as a mail to
 *  Montana's address, reviewed within 24 hours. A post is reported the same way (iOS MTBoardSheet.reporting): its writer when this
 *  machine knows them, and then they may be blocked with it; a writer the wall never named is reported through the wall that
 *  carried the post (`who` -- the name the post carried), and nobody is blocked for another's words (`blocks` false). */
export function ReportPage({ chat, name, letter, who, blocks = true, onClose }) {
  const [reason, setReason] = useState("spam");
  const [block, setBlock] = useState(blocks);
  const [noMail, setNoMail] = useState(false);
  const send = async () => {
    if (block && blocks) await invoke("chat_block", { chat, on: true });
    const ok = await invoke("report", { chat, reason, mid: letter?.mid ?? null, text: letter?.text ?? null, who: who ?? null });
    if (ok) onClose(); else setNoMail(true);
  };
  // iOS MontanaReportSheet: the cross, the reasons, the letter's words grey (six lines at most), «also block» in its own section, then
  // «Send report» in the accent and the address line under it in the same section
  return (
    <Page title={t("Report")} onClose={onClose}>
      <Section head={t("Reason")}>
        {REASONS.map(([k, label]) => (
          <button key={k} className="set-row lang" onClick={() => setReason(k)}>
            <span className="row-title">{t(label)}</span>{reason === k && <span className="tick-mark">✓</span>}
          </button>
        ))}
      </Section>
      {letter?.text && (
        <Section head={t("The reported letter")}>
          <div className="set-row"><span className="row-title report-letter">{letter.text}</span></div>
        </Section>
      )}
      {blocks && <Section><Toggle title={t("Also block this person")} on={block} onChange={setBlock} /></Section>}
      <Section>
        <button className="set-row" onClick={send}><span className="row-title accent-word">{t("Send report")}</span></button>
        <div className="set-row"><span className="row-title report-foot">{t("Reports go to %@ and are reviewed within 24 hours.", { "%@": "contact@montana.quest" })}</span></div>
      </Section>
      {noMail && (
        <div className="alert-shade" onClick={onClose}>
          <div className="alert" role="alertdialog" onClick={(e) => e.stopPropagation()}>
            <div className="alert-title">{t("There is no mail program on this computer. The report and our address are copied — paste them into any mail.")}</div>
            <button onClick={onClose}>{t("OK")}</button>
          </div>
        </div>
      )}
    </Page>
  );
}

/** THE BLOCKED (iOS MontanaSafety 246-266): each with «Unblock»; none: «Nobody is blocked.» */
export function BlockedPage({ onClose }) {
  const [list, setList] = useState(null);
  const look = () => invoke("blocked_list").then(setList);
  useEffect(() => { look(); }, []);
  return (
    <Page title={t("Blocked users")} onClose={onClose} back>
      <Section>
        {list && list.length === 0 && <div className="set-row"><span className="row-title">{t("Nobody is blocked.")}</span></div>}
        {(list || []).map(([r, name]) => (
          <div key={r} className="set-row">
            <span className="row-title">{chatName(name)}</span>
            <button className="unblock" onClick={async () => { await invoke("chat_block", { chat: r, on: false }); setTimeout(look, 300); }}>{t("Unblock")}</button>
          </div>
        ))}
      </Section>
    </Page>
  );
}
