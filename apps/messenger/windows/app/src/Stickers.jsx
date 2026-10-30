import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { drawableUrl, isHeif, useFile } from "./Media.jsx";
import { useChanged } from "./Chats.jsx";

/** One sticker of the book, by its name here (the picture lies in the media store beside every other picture, as in iOS). */
function Pic({ name }) {
  const url = useFile(name, true, name.split(".").pop());
  return url ? <img src={url} alt="" /> : null;
}

/** A picture made ready to be a sticker (iOS MontanaStickerCut.fit): the long side at most 512, nothing scaled up, its
 *  transparency kept (PNG); a GIF goes untouched. Windows has no «lift subject»: a photo stays the rectangle it is. */
async function ready(file) {
  if (file.type === "image/gif") return new Uint8Array(await file.arrayBuffer());
  const url = await drawableUrl(file);
  try {
    const img = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = no; i.src = url; });
    const k = Math.min(1, 512 / Math.max(img.naturalWidth, img.naturalHeight));
    const c = document.createElement("canvas");
    c.width = Math.max(1, Math.round(img.naturalWidth * k)); c.height = Math.max(1, Math.round(img.naturalHeight * k));
    c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
    const blob = await new Promise((ok) => c.toBlob(ok, "image/png"));
    return new Uint8Array(await blob.arrayBuffer());
  } finally {
    URL.revokeObjectURL(url);
  }
}

/** THE STICKERS' PANEL (iOS MontanaStickerScreens): my set first -- a picture added becomes my sticker, a right click takes one
 *  out --, then the sets met through others' letters, each asked of the one who handed it over, then the emoji drawn large. */
export function StickerPanel({ onPick, emoji, onEmoji }) {
  const [book, setBook] = useState(null);
  const [asked, setAsked] = useState({});
  const picker = useRef(null);
  const look = () => invoke("stickers_state").then(setBook).catch(() => {});
  useEffect(() => { look(); }, []);
  useChanged(look);
  const add = async (files) => {
    for (const f of files) {
      if (!f.type.startsWith("image/") && !isHeif(f)) continue;   // a HEIC comes with no type of its own
      try { await invoke("sticker_add", await ready(f)); } catch { /* a picture the window cannot read is no sticker */ }
    }
    look();
  };
  return (
    <div className="sticker-panel">
      <div className="sticker-head">
        <b>{t("My stickers")}</b>
        <button onClick={() => picker.current?.click()} aria-label={t("Add Sticker")}>＋ {t("Add Sticker")}</button>
        <input ref={picker} type="file" accept="image/png,image/webp,image/gif,image/jpeg,image/heic,image/heif,.heic,.heif" multiple hidden
               onChange={(e) => { add([...e.target.files]); e.target.value = ""; }} />
      </div>
      <div className="sticker-grid">
        {(book?.mine || []).map((n, i) => (
          <button key={n} onClick={() => onPick(n)} aria-label={`${t("My sticker")} ${i + 1}`}
                  onContextMenu={(e) => { e.preventDefault(); invoke("sticker_forget", { name: n }).then(look); }}><Pic name={n} /></button>
        ))}
        {book && !book.mine.length && <div className="row-caption">{t("Add a picture: it becomes your sticker.")}</div>}
      </div>
      {(book?.packs || []).map((p) => (
        <div key={p.id} className="sticker-set">
          <div className="sticker-head">
            <b>{p.title}</b>
            {p.names.length < Math.max(1, p.expected) && (asked[p.id]
              ? <span className="row-caption">{t("Ask the person who sent this set for it.")}</span>
              : <button onClick={() => invoke("sticker_ask", { pack: p.id }).then((ok) => setAsked((a) => ({ ...a, [p.id]: ok })))} aria-label={`${t("Get the set")}: ${p.title}`}>{t("Get the set")}</button>)}
          </div>
          <div className="sticker-grid">
            {p.names.map((n, i) => <button key={n} onClick={() => onPick(n)} aria-label={`${p.title} ${i + 1}`}><Pic name={n} /></button>)}
          </div>
        </div>
      ))}
      <div className="sticker-head"><b>{t("Emoji")}</b></div>
      <div className="emoji-grid big">
        {emoji.map((e) => <button key={e} aria-label={e} onClick={() => onEmoji(e)}>{e}</button>)}
      </div>
    </div>
  );
}

/** A STICKER LETTER'S OWN SHEET (iOS «View sticker set»): its set, to be asked for when it is not held, and the picture to keep in
 *  my set. */
export function StickerSheet({ mid, onClose }) {
  const [p, setP] = useState(undefined);
  const [said, setSaid] = useState(null);
  useEffect(() => { invoke("sticker_passport", { mid }).then(setP).catch(() => setP(null)); }, [mid]);
  if (p === undefined) return null;
  return (
    <div className="menu-shade" onClick={onClose}>
      <div className="letter-menu" onClick={(e) => e.stopPropagation()} role="menu" aria-label={t("Sticker")}>
        <div className="menu-rows">
          {p && <div className="menu-row" aria-hidden="true"><span>{p.title}</span></div>}
          {p && !p.held && <button className="menu-row" role="menuitem" onClick={async () => { const ok = await invoke("sticker_ask", { pack: p.pack }).catch(() => false); setSaid(ok ? t("Ask the person who sent this set for it.") : null); if (!ok) onClose(); }}><span>{t("Get the set")}</span></button>}
          <button className="menu-row" role="menuitem" onClick={() => { invoke("sticker_adopt", { mid }).finally(onClose); }}><span>{t("Add to My Stickers")}</span></button>
          {said && <div className="menu-row" role="status"><span className="row-caption">{said}</span></div>}
        </div>
      </div>
    </div>
  );
}
