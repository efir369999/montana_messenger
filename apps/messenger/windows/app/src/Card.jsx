import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { sendFile } from "./Media.jsx";
import { ForwardSheet } from "./Conversation.jsx";
import logo from "./assets/logo.png";

/** The card's mark ahead of its words in the caption its photo rides with (iOS MontanaCardPlate.mark): every build reads it. */
export const CARD_MARK = "📇 ";
/** ISO/IEC 7810 ID-1, 85.60 by 53.98 millimetres -- the one standard size a card has (iOS MontanaCardPlate.aspect). */
const ASPECT = 85.6 / 53.98;
/** The brushed gold of the plate, its stops as iOS lays them (MontanaCardPlate.metal). */
const METAL = [["#9e7324", 0], ["#edc25c", 0.28], ["#fce594", 0.46], ["#e0ad45", 0.62], ["#a87821", 1]];
const INK = "#291c05", INK_SOFT = "#4d3609";

/** The lines a card carries, in its order: the name, then every way to reach the person that is filled in (iOS lines). */
export function cardLines(c) {
  if (!c) return [];
  const ways = [c.phone, c.email, ...String(c.other || "").split(/\r?\n/)].map((w) => (w || "").trim()).filter(Boolean);
  return [(c.name || "").trim(), ...ways];
}
/** What a line is (iOS MontanaCardLine.read): a phone number, an e-mail, a link, or the person's own words. */
function kindOf(line) {
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(line)) return "email";
  if (/^(https?:\/\/|www\.)\S+$/i.test(line) || /^[\w-]+(\.[\w-]+)+\/?\S*$/.test(line) && !/^\+?[\d\s().-]+$/.test(line)) return "link";
  if (/^\+?[\d\s().-]{6,}$/.test(line) && (line.match(/\d/g) || []).length >= 6) return "phone";
  return "words";
}
const GLYPH = { phone: "phone", email: "paperplane", link: "link", words: "chats" };
/** The ways the face has room for: four lines under the name; a fifth and more stand on the fourth (iOS shown). */
function shown(lines) {
  const ways = lines.slice(1).filter(Boolean);
  return ways.length <= 4 ? ways : [...ways.slice(0, 3), ways.slice(3).join(" · ")];
}

/** THE CARD'S ONE FACE (iOS MontanaCardFace): the name large at the top, each way to reach the person on its own line behind
 *  the glyph of what it is, on the gold plate, the emblem embossed on the right. */
export function CardFace({ lines, width = 340 }) {
  const h = width / ASPECT;
  return (
    <div className="card-face" style={{ width, height: h, background: `linear-gradient(135deg, ${METAL.map(([c, p]) => `${c} ${p * 100}%`).join(", ")})` }}
         role="img" aria-label={lines.filter(Boolean).join(", ") || t("Business card")}>
      <img src={logo} alt="" className="card-emblem" style={{ height: h * 0.7, right: h * 0.08 }} />
      <div className="card-name" style={{ fontSize: Math.round(width * 0.075) }}>{lines[0] || ""}</div>
      <div className="card-ways" style={{ fontSize: Math.round(width * 0.04) }}>
        {shown(lines).map((w, i) => (
          <div key={i} className="card-way"><Glyph name={GLYPH[kindOf(w)]} size={Math.round(width * 0.045)} color={INK_SOFT} /><span>{w}</span></div>
        ))}
      </div>
    </div>
  );
}

/** THE CARD AS A PHOTO OF THE STANDARD SIZE (iOS photo): the face drawn full bleed at 1600 by 1008, a JPEG as every photo of
 *  the app leaves. */
async function cardPhoto(lines) {
  const W = 1600, H = Math.round(W / ASPECT);
  const c = document.createElement("canvas");
  c.width = W; c.height = H;
  const g = c.getContext("2d");
  const grad = g.createLinearGradient(0, 0, W, H);
  for (const [col, p] of METAL) grad.addColorStop(p, col);
  g.fillStyle = grad; g.fillRect(0, 0, W, H);
  const img = await new Promise((ok) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => ok(null); i.src = logo; });
  if (img) {
    const lh = H * 0.7, lw = lh * (img.naturalWidth / img.naturalHeight);
    g.save(); g.globalAlpha = 0.32; g.globalCompositeOperation = "multiply";
    g.drawImage(img, W - lw - H * 0.08, (H - lh) / 2, lw, lh);
    g.restore();
  }
  g.fillStyle = INK; g.textBaseline = "top";
  g.font = `700 ${Math.round(W * 0.075)}px "Segoe UI", sans-serif`;
  g.fillText(lines[0] || "", W * 0.07, H * 0.1, W * 0.62);
  const ways = shown(lines);
  const size = Math.round(W * 0.04);
  g.font = `500 ${size}px "Segoe UI", sans-serif`;
  g.fillStyle = INK_SOFT;
  const mark = { phone: "☎", email: "✉", link: "🔗", words: "•" };
  ways.forEach((w, i) => {
    const y = H * 0.9 - (ways.length - i) * size * 1.45;
    g.fillText(`${mark[kindOf(w)]}  ${w}`, W * 0.07, y, W * 0.62);
  });
  return new Promise((ok) => c.toBlob(ok, "image/jpeg", 0.9));
}

/** The card sent to a conversation: its photo, its words under the mark as the caption. */
export async function sendCard(chat, lines) {
  const blob = await cardPhoto(lines);
  if (!blob) throw new Error("photo");
  const file = new File([blob], "card.jpg", { type: "image/jpeg" });
  return sendFile(chat, file, CARD_MARK + lines.filter(Boolean).join("\n"), null);
}

/** THE BUSINESS CARD PAGE (iOS MontanaCardNoteView): the face drawn live, the name and the ways to reach the person, kept after a
 *  typing pause; «Отправить» hands it to a conversation as a photo (Windows has no share sheet of the system). */
export default function CardPane() {
  const [card, setCard] = useState(null);
  const [sending, setSending] = useState(false);
  const [said, setSaid] = useState(null);
  useEffect(() => { invoke("card_get").then(setCard).catch(() => setCard({ name: "", phone: "", email: "", other: "" })); }, []);
  useEffect(() => {
    if (!card) return;
    const id = setTimeout(() => invoke("card_set", { card }).catch(() => {}), 700);
    return () => clearTimeout(id);
  }, [card]);
  if (!card) return null;
  const lines = cardLines(card);
  const empty = lines.every((l) => !l);
  const field = (key, label, multi) => (
    <label className="card-field">
      <span className="row-caption">{t(label)}</span>
      {multi
        ? <textarea rows={3} value={card[key]} aria-label={t(label)} onChange={(e) => setCard({ ...card, [key]: e.target.value })} />
        : <input value={card[key]} aria-label={t(label)} onChange={(e) => setCard({ ...card, [key]: e.target.value })} />}
    </label>
  );
  return (
    <div className="card-pane">
      <div className="card-pane-head"><b>{t("Business card")}</b>
        <button className="send-card" disabled={empty} onClick={() => setSending(true)} aria-label={t("Send")}><Glyph name="paperplane" size={18} color="#fff" /><span>{t("Send")}</span></button>
      </div>
      <CardFace lines={lines} width={340} />
      <div className="card-fields">
        {field("name", "Name")}
        {field("phone", "Phone")}
        {field("email", "E-mail")}
        {field("other", "Other ways to reach you", true)}
      </div>
      <div className="sect-foot">{t("This is your business card: keep it and hand it to anyone — your personal contacts and how to reach you: phone, e-mail and other ways. It leaves as a photo, and whoever receives it can save it to their contacts.")}</div>
      {said && <div className="row-caption" role="status">{said}</div>}
      {sending && <ForwardSheet title={t("Send")} onClose={() => setSending(false)}
                                onPick={async (to) => { setSending(false); invoke("card_set", { card }).catch(() => {}); try { await sendCard(to, lines); setSaid(t("Sent")); } catch { setSaid(t("Not sent")); } }} />}
    </div>
  );
}
