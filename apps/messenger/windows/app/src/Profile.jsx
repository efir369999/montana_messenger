import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { Face, SAVED, SelfFace, chatName } from "./Chats.jsx";
import { Page, Section, Row, Waiting } from "./Settings.jsx";
import { BlockSheet, ReportPage } from "./Safety.jsx";
import { GroundPicker, PAGE, TheirGround } from "./Ground.jsx";
import { drawableUrl } from "./Media.jsx";
import { useLeave } from "./leave.js";
import { Wall } from "./Wall.jsx";
import { forgetSmallFaces } from "./WallMedia.jsx";
import { PeerPanes } from "./PeerPanes.jsx";
import { PlayerBar } from "./PlayerBar.jsx";

/** EVERY LINK OF THE PAGE'S FIELD (iOS 2304 MTFaceHeader.links over MTPeerAbout.links): a bubble for each link, the site and
 *  the path without the scheme (MTPeerAbout.shown), opened by the system's browser; the field arrives as its links, one space
 *  apart -- a word that is not the web never stood in it. */
function Links({ field }) {
  const links = (field || "").split(/[\s,]+/).filter((u) => /^https?:\/\//i.test(u));
  const shown = (u) => u.replace(/^https?:\/\//i, "").replace(/\/$/, "");
  return links.map((u) => (
    <button key={u} className="me-bubble link" title={u} onClick={() => invoke("open_link", { url: u })}>{shown(u)}</button>
  ));
}

/** MY PAGE (iOS MontanaMyProfileView): my face, my name, my words about myself and my link, as my correspondents read them;
 *  «…» edits; my wall under them. */
export function MyPage({ person, onClose, onChanged }) {
  const [s, setS] = useState(null);
  const [editing, setEditing] = useState(false);
  const look = () => invoke("settings_get").then(setS);
  useEffect(() => { look(); }, []);
  if (editing) return <Editor person={person} onDone={() => { setEditing(false); look(); onChanged(); }} />;
  return (
    <Page title="" onClose={onClose} back
          right={<button className="glass-mark" onClick={() => setEditing(true)} aria-label={t("Edit")}><Glyph name="more" size={20} color="var(--bar-glyph)" /></button>}>
      <div className="me-head">
        <SelfFace name={person.name} version={person.face} size={104} />
        <div className="me-bubble name">{person.name}</div>
        {s?.profileBio && <div className="me-bubble">{s.profileBio}</div>}
        <Links field={s?.profileLink} />
      </div>
      <Wall wall={null} />
    </Page>
  );
}

/** A picture made into my face (iOS MTAvatarCropView): the square the person frames -- dragged and zoomed -- rendered at
 *  640×640, JPEG on black, the quality stepping down until it fits 128 KiB; a group's face is the same square at 160 within
 *  the 18 000 bytes its invitation carries (iOS MTGroup.thumb). */
/** CHOOSING A CALL SIGN (iOS MontanaCallsignPicker): the same rows the default comes from, in this person's language, searched;
 *  the choice is the person's and it stays theirs, exactly like a name they would have typed. */
export function CallsignPicker({ current, onPick, onClose }) {
  const [rows, setRows] = useState([]);
  const [q, setQ] = useState("");
  useEffect(() => { invoke("callsigns").then(setRows).catch(() => {}); }, []);
  const shown = rows.filter((r) => !q.trim() || r.toLowerCase().includes(q.trim().toLowerCase()));
  return (
    <Page title={t("Call sign")} onClose={onClose} back>
      <Section>
        <input className="set-field" placeholder={t("Search")} value={q} aria-label={t("Search")} onChange={(e) => setQ(e.target.value)} />
      </Section>
      <Section>
        {shown.map((r) => (
          <button key={r} className="set-row" onClick={() => onPick(r)} aria-label={`${t("Call sign")}: ${r}`}>
            <span className="row-title">{r}</span>{r === current && <Glyph name="tick" size={18} color="var(--blue)" />}
          </button>
        ))}
      </Section>
    </Page>
  );
}

export function Crop({ file, onDone, onCancel, out = 640, limit = 131072, q0 = 0.85 }) {
  const [img, setImg] = useState(null);
  useLeave(onCancel);   // Esc, the mouse's back button, Alt+← -- its cross, never the page waiting under it
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const drag = useRef(null);
  const side = 320;
  useEffect(() => {
    let u = null, live = true;
    drawableUrl(file).then((x) => {
      u = x;
      if (!live) return URL.revokeObjectURL(u);
      const i = new Image();
      i.onload = () => setImg(i);
      i.src = u;
    });
    return () => { live = false; if (u) URL.revokeObjectURL(u); };
  }, [file]);
  // THE CROP STANDS AT ONCE (iOS MTAvatarCropView in a fullScreenCover, MontanaProfile.swift 810-811; iOS has the picture before
  // the cover rises, a window reads it here -- a HEIC is converted first): its ground, its cross and a spinner while it is read,
  // never nothing over a page that waits under it
  if (!img) {
    return (
      <div className="crop" role="dialog">
        <div className="crop-bar">
          <button className="glass-mark" onClick={onCancel} aria-label={t("Cancel")}><Glyph name="close" size={18} color="#fff" /></button>
        </div>
        <span className="spinner" role="status" />
      </div>
    );
  }
  const base = side / Math.min(img.naturalWidth, img.naturalHeight);   // the picture always covers the frame
  const k = base * zoom, w = img.naturalWidth * k, h = img.naturalHeight * k;
  const clamp = (p) => ({ x: Math.min(0, Math.max(side - w, p.x)), y: Math.min(0, Math.max(side - h, p.y)) });
  const at = clamp({ x: (side - w) / 2 + pan.x, y: (side - h) / 2 + pan.y });
  const done = async () => {
    const c = document.createElement("canvas");
    c.width = c.height = out;
    const g = c.getContext("2d");
    g.fillStyle = "#000"; g.fillRect(0, 0, out, out);
    const f = out / side;
    g.drawImage(img, at.x * f, at.y * f, w * f, h * f);
    for (let q = q0; q >= 0.3; q -= 0.05) {
      const b = await new Promise((ok) => c.toBlob(ok, "image/jpeg", q));
      if (b.size <= limit) return onDone(new Uint8Array(await b.arrayBuffer()));
    }
  };
  return (
    <div className="crop" role="dialog">
      <div className="crop-bar">
        <button className="glass-mark" onClick={onCancel} aria-label={t("Cancel")}><Glyph name="close" size={18} color="#fff" /></button>
        <button className="glass-mark" onClick={done} aria-label={t("Done")}><Glyph name="tick" size={18} color="#fff" /></button>
      </div>
      <div className="crop-frame" style={{ width: side, height: side }}
           onPointerDown={(e) => { drag.current = { x: e.clientX, y: e.clientY, p: at }; e.currentTarget.setPointerCapture(e.pointerId); }}
           onPointerMove={(e) => { const d = drag.current; if (d) setPan({ x: d.p.x + e.clientX - d.x - (side - w) / 2, y: d.p.y + e.clientY - d.y - (side - h) / 2 }); }}
           onPointerUp={() => { drag.current = null; }}
           onWheel={(e) => setZoom((z) => Math.min(5, Math.max(1, z * (e.deltaY < 0 ? 1.1 : 0.9))))}>
        <img src={img.src} alt="" style={{ left: at.x, top: at.y, width: w, height: h }} draggable={false} />
      </div>
      <input className="crop-zoom" type="range" min="1" max="5" step="0.01" value={zoom} aria-label="zoom" onChange={(e) => setZoom(+e.target.value)} />
    </div>
  );
}

/** THE EDITOR OF MY PAGE (iOS ProfileView): the face (choose, change, remove), the name, my words about myself and my link;
 *  the checkmark saves. My correspondents hear the changes with the next walk. */
function Editor({ person, onDone }) {
  const [s, setS] = useState(null);
  const [name, setName] = useState(person.name);
  const [bio, setBio] = useState("");
  const [link, setLink] = useState("");
  const [file, setFile] = useState(null);
  const [menu, setMenu] = useState(false);
  const [face, setFace] = useState(person.face);
  const picker = useRef(null);
  useEffect(() => { invoke("settings_get").then((x) => { setS(x); setBio(x.profileBio || ""); setLink(x.profileLink || ""); }); }, []);
  const save = async () => {
    if (name.trim() !== person.name) await invoke("identity_set_name", { name });
    await invoke("setting_set", { key: "profileBio", value: bio });
    await invoke("setting_set", { key: "profileLink", value: link });
    onDone();
  };
  const setPhoto = async (bytes) => {
    await invoke("face_set", bytes);
    forgetSmallFaces();   // the small faces my posts and comments carry are drawn again from the new one
    const st = await invoke("identity_state");
    setFace(st.face); setFile(null);
  };
  const [picking, setPicking] = useState(false);   // the call signs listed
  const [ground, setGround] = useState(false);     // my page's ground being chosen
  if (file) return <Crop file={file} onCancel={() => setFile(null)} onDone={setPhoto} />;
  if (ground) return <GroundPicker conv={PAGE} onClose={() => setGround(false)} />;
  return (
    <Page title="" onClose={onDone} back
          right={<button className="glass-mark" onClick={save} aria-label={t("Done")}><Glyph name="tick" size={18} color="var(--bar-glyph)" /></button>}>
      <input ref={picker} type="file" accept="image/*,.heic,.heif" hidden onChange={(e) => { if (e.target.files[0]) setFile(e.target.files[0]); e.target.value = ""; }} />
      <div className="me-head">
        <SelfFace name={name} version={face} size={108} onClick={() => (face ? setMenu(true) : picker.current.click())} />
      </div>
      <Section>
        <button className="set-row accent" onClick={() => (face ? setMenu(true) : picker.current.click())}>
          <Glyph name="photo" size={18} color="#fff" /><span className="row-title">{face ? t("Change photo") : t("Choose photo")}</span>
        </button>
        <Row icon="photo" color="#636366" title={t("Change page background")} onClick={() => setGround(true)} />
      </Section>
      <Section>
        <input className="set-field" placeholder={t("First name")} value={name} maxLength={64} aria-label={t("First name")} onChange={(e) => setName(e.target.value)} />
        <Row icon="personCircle" color="#636366" title={t("Choose a call sign")} onClick={() => setPicking(true)} />
      </Section>
      {picking && <CallsignPicker current={name} onPick={(r) => { setName(r); setPicking(false); }} onClose={() => setPicking(false)} />}
      <Section foot={t("Your bio and link are seen by the people you write to.")}>
        <textarea className="set-field" rows={3} placeholder={t("Bio")} value={bio} maxLength={140} aria-label={t("Bio")} onChange={(e) => setBio(e.target.value)} />
        <input className="set-field" placeholder={t("Link")} value={link} aria-label={t("Link")} onChange={(e) => setLink(e.target.value)} />
      </Section>
      {menu && (
        <div className="menu-shade" onClick={() => setMenu(false)}>
          <div className="letter-menu" style={{ left: "50%", top: 200, transform: "translateX(-50%)" }} onClick={(e) => e.stopPropagation()} role="menu">
            <div className="menu-rows">
              <button className="menu-row" onClick={() => { setMenu(false); picker.current.click(); }}><span>{t("Change photo")}</span><Glyph name="photo" size={18} /></button>
              <button className="menu-row red" onClick={async () => { setMenu(false); await invoke("face_set", new Uint8Array(0)); forgetSmallFaces(); setFace(0); }}>
                <span>{t("Remove photo")}</span><Glyph name="trash" size={18} />
              </button>
            </div>
          </div>
        </div>
      )}
    </Page>
  );
}

/** A CORRESPONDENT'S PAGE (iOS PeerInfo): their face, name, words about themselves and link. */
export function PeerPage({ chat, face, myName, onClose, onWrite, onShowLetter, onForward }) {
  const [p, setP] = useState(null);
  const [failed, setFailed] = useState(false);   // their words did not come
  const [blocked, setBlocked] = useState(false);
  const [asking, setAsking] = useState(false);
  const [reporting, setReporting] = useState(false);
  const [editing, setEditing] = useState(null);   // {first, last} while my name for them is written (iOS edit mode)
  const [original, setOriginal] = useState(false);
  const [ground, setGround] = useState(false);   // the chat's ground being chosen
  const look = () => {
    invoke("peer_about", { chat }).then((x) => { setFailed(false); setP(x); }, () => setFailed(true));
    invoke("chat_open", { chat }).then((c) => setBlocked(!!c?.blocked)).catch(() => {});
  };
  useEffect(() => { look(); }, [chat]);
  // SAVED MESSAGES IS ITS PANES (iOS MontanaPeerInfoScreen 58-64, the author's word 18.09): the room without an address has no face,
  // no name and no actions to show -- its page opens straight on the strip of what it holds, with no title over it
  if (chat === SAVED) {
    return (
      <Page key="saved" title="" onClose={onClose} back>
        <PeerPanes chat={chat} name="" myName={myName} onShowLetter={onShowLetter} onForward={onForward} />
        <div className="player-foot"><PlayerBar /></div>
      </Page>
    );
  }
  const [name, bio, link, alias, theirs] = p || [];
  if (reporting) return <ReportPage chat={chat} name={name} onClose={() => { setReporting(false); look(); }} />;
  if (ground) return <GroundPicker conv={chat} onClose={() => setGround(false)} />;
  const done = async () => { await invoke("peer_rename", { chat, first: editing.first, last: editing.last }); setEditing(null); look(); };
  const edit = () => {
    const shown = (alias || theirs || "").trim();
    const cut = shown.indexOf(" ");
    setEditing(cut > 0 ? { first: shown.slice(0, cut), last: shown.slice(cut + 1) } : { first: shown, last: "" });
  };
  // THE PAGE STANDS AT ONCE, ON THEIR GROUND (the freeze of the panel's first slot, 25.10.2026): its frame while their words are read,
  // never nothing over an app it has made inert; MY NAME FOR THEM is written on a page pushed over it (iOS edit mode), the page
  // waiting under it as it stood
  return (
    <>
      <Page key="peer" title="" onClose={onClose} back ground={<TheirGround chat={chat} />} under={!!editing}
            right={p && <button className="glass-mark" onClick={edit} aria-label={t("Edit")}><Glyph name="pencil" size={18} color="#fff" /></button>}>
        {!p ? <Section><Waiting failed={failed} onRetry={look} /></Section> : <>
          <div className="me-head">
            <Face chat={chat} version={face} size={104} />
            <div className="me-bubble name">{chatName(name)}</div>
            {bio && <div className="me-bubble">{bio}</div>}
            <Links field={link} />
          </div>
          {blocked && <div className="me-head"><span className="blocked-pill">{t("Blocked")}</span></div>}
          <Section>
            <button className="set-row accent" onClick={onWrite}><Glyph name="compose" size={18} color="#fff" /><span className="row-title">{t("Write")}</span></button>
            <Row icon="photo" color="#636366" title={t("Chat background")} onClick={() => setGround(true)} />
          </Section>
          <Section>
            <button className="set-row" onClick={() => (blocked ? invoke("chat_block", { chat, on: false }).then(() => setTimeout(look, 300)) : setAsking(true))}>
              <Glyph name="nosign" size={18} color="var(--red)" /><span className="row-title red">{blocked ? t("Unblock") : t("Block")}</span>
            </button>
            <button className="set-row" onClick={() => setReporting(true)}>
              <Glyph name="report" size={18} color="var(--red)" /><span className="row-title red">{t("Report")}</span>
            </button>
          </Section>
          {/* THE PANES (iOS MontanaPeerInfoScreen.panes): the strip, then the wall or what the chat holds */}
          <PeerPanes chat={chat} name={name} myName={myName} onShowLetter={onShowLetter} onForward={onForward} />
          {/* THE MINI PLAYER STANDS HERE TOO (iOS MontanaPeerInfoScreen: the same bar as the chat's and the list's) */}
          <div className="player-foot"><PlayerBar /></div>
          {asking && <BlockSheet name={name} onClose={() => setAsking(false)}
                                 onBlock={async () => { setAsking(false); await invoke("chat_block", { chat, on: true }); setTimeout(look, 300); }} />}
        </>}
      </Page>
      {p && editing && (
        <Page key="edit" title={t("Edit")} onClose={() => setEditing(null)} back
              right={<button className="glass-mark" onClick={done} aria-label={t("Done")}><Glyph name="tick" size={18} color="#fff" /></button>}>
          <div className="me-head"><Face chat={chat} version={face} size={104} /></div>
          <Section foot={alias && theirs && original ? theirs : null}>
            <input className="set-field" placeholder={t("First name")} aria-label={t("First name")} value={editing.first} maxLength={64}
                   onChange={(e) => setEditing({ ...editing, first: e.target.value })} />
            <input className="set-field" placeholder={t("Last name")} aria-label={t("Last name")} value={editing.last} maxLength={64}
                   onChange={(e) => setEditing({ ...editing, last: e.target.value })} />
            {alias && theirs && <button className="set-row" onClick={() => setOriginal(!original)}><span className="row-title" style={{ color: "var(--blue)" }}>{t("Show original name")}</span></button>}
          </Section>
        </Page>
      )}
    </>
  );
}
