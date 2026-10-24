import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";

// THE TERMS (MontanaSafety.swift, MontanaTermsView): plain sentences in the platform's list style, the same text from the
// gate and from Settings. iOS MontanaSafety.contactMail and .site.
const MAIL = "contact@montana.quest";

const SECTIONS = [
  [null, ["Montana is a messenger between people who chose to talk to each other. Every conversation is encrypted end to end; nobody but the people in it can read it.",
          "By using Montana you agree to these terms."]],
  ["No tolerance for abuse", ["There is no tolerance for objectionable content or abusive users: threats, harassment, hate speech, sexual content involving minors, spam and any content that breaks the law.",
                              "You must be 18 or older to use Montana.",
                              "A person who sends such content or abuses others is barred from Montana's relays and doors."]],
  ["Your tools", ["Block: a blocked person can no longer reach you — their letters and calls are refused on every road and never shown.",
                  "Report: any letter or person can be reported from its menu. Reports are reviewed within 24 hours; offending content is removed and the offender is barred.",
                  "Filter: letters carrying objectionable words are folded by default and unfold only by your tap. The filter is yours to keep or turn off in Privacy.",
                  "Delete: any letter can be removed from your feed at once — for you, or for everyone."]],
];

export function TermsView({ gate = false, onAgree }) {
  return (
    <div className="terms">
      <div className="terms-title">{t("Terms of Use")}</div>
      <div className="terms-list">
        {SECTIONS.map(([head, rows], i) => (
          <section key={i}>
            {head && <div className="terms-head">{t(head)}</div>}
            <div className="terms-group">{rows.map((r) => <div className="terms-row" key={r}>{t(r)}</div>)}</div>
          </section>
        ))}
        <section>
          <div className="terms-head">{t("Reach us")}</div>
          <div className="terms-group">
            <a className="terms-row link" href="#" onClick={(e) => { e.preventDefault(); invoke("open_site", { page: "mail" }); }}>{MAIL}</a>
            <a className="terms-row link" href="#" onClick={(e) => { e.preventDefault(); invoke("open_site", { page: "site" }); }}>https://montana.quest</a>
          </div>
        </section>
      </div>
      {gate && <div className="doors terms-door"><button className="door door-blue" onClick={onAgree}>{t("I agree")}</button></div>}
    </div>
  );
}
