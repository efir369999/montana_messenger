import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { useLeave } from "./leave.js";
import { invoke } from "@tauri-apps/api/core";
import { t, locale, dayWord } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { BIG, GIF_NAME, sizeText, urlOf, useFile } from "./Media.jsx";
import PhotoAlbum from "./PhotoAlbum.jsx";
import { chatName, hourOf } from "./Chats.jsx";
import { count as coinCount, foldHistory, KIND_GLYPH } from "./Wallet.jsx";
import { Wall } from "./Wall.jsx";
import { ForwardGlyph, MenuRow } from "./Conversation.jsx";
import * as player from "./player.js";
import { stem } from "./player.js";

/** THE PANES OF A CORRESPONDENT'S PAGE (iOS MTMediaTab, MontanaPeerInfoScreen.panes): the wall first, then the coins moved with them,
 *  then what the chat holds -- its pictures, its films, its files, its links, its music, its voices -- each by day, the newest first. */
export const TABS = [
  ["wall", "Wall", "No posts yet"],
  ["transactions", "Transactions", "No transactions yet"],
  ["media", "Media", "Shared media will appear here"],
  ["video", "Video", "Shared video will appear here"],
  ["files", "Files", "Shared files will appear here"],
  ["links", "Links", "Shared links will appear here"],
  ["music", "Music", "Shared music will appear here"],
  ["voice", "Voice", "Shared voice messages will appear here"],
];
const AUDIO = ["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "caf"];   // iOS mtIsAudioName
const isMusic = (f) => f.m.k === "doc" && (AUDIO.includes((f.m.e || "").toLowerCase()) || AUDIO.includes(((f.m.n || "").split(".").pop() || "").toLowerCase()));

const dayLabel = dayWord;
/** The items by day, the newest day first and the newest item first in it (iOS byDay: the items reversed). */
function byDay(items, at) {
  const out = [];
  for (const x of [...items].sort((a, b) => at(b) - at(a))) {
    const d = dayLabel(at(x));
    if (out.length && out[out.length - 1].day === d) out[out.length - 1].items.push(x); else out.push({ day: d, items: [x] });
  }
  return out;
}

/** THE TAB STRIP (iOS MTTabStrip): a capsule 44 tall on the one-tone glass; the words 15 medium in grey, the chosen one white over
 *  the pill (systemGray4, 3 in) that slides to it on the platform's spring (0.4 s, damping 0.85); while the words fit they share the
 *  width evenly, else each keeps its own and the strip rolls, the chosen word brought into view with 100 of the next beside it. */
export function TabStrip({ tabs, tab, onTab }) {
  const track = useRef(null);
  const [fit, setFit] = useState(true);
  const [pill, setPill] = useState(null);
  useLayoutEffect(() => {
    const el = track.current;
    if (!el) return;
    const lay = () => {
      const words = [...el.querySelectorAll(".tab-word")];
      const natural = words.reduce((s, b) => s + Math.ceil(b.firstChild.getBoundingClientRect().width) + 32, 0);
      setFit(natural <= el.clientWidth - 6);
    };
    lay();
    const ro = new ResizeObserver(lay);
    ro.observe(el);
    return () => ro.disconnect();
  }, [tabs.length]);
  useLayoutEffect(() => {
    const el = track.current;
    const b = el?.querySelector(`[data-tab="${tab}"]`);
    if (!b) return;
    setPill({ left: b.offsetLeft, width: b.offsetWidth });
    // the chosen word rides into view, a hundred points of the next one beside it
    const w = el.clientWidth;
    let ox = el.scrollLeft;
    if (ox + w - 100 < b.offsetLeft + b.offsetWidth) ox = b.offsetLeft + b.offsetWidth - w + 100;
    if (ox > b.offsetLeft - 100) ox = b.offsetLeft - 100;
    el.scrollTo({ left: Math.max(0, ox), behavior: "smooth" });
  }, [tab, fit]);
  return (
    <div className="tab-strip" role="tablist" ref={track}>
      {pill && <span className="tab-pill" style={{ left: pill.left, width: pill.width }} aria-hidden="true" />}
      {tabs.map(([k, w]) => (
        <button key={k} data-tab={k} role="tab" aria-selected={tab === k} className={"tab-word" + (tab === k ? " on" : "") + (fit ? " even" : "")}
                onClick={() => onTab(k)}><span>{t(w)}</span></button>
      ))}
    </div>
  );
}

/** A PLAIN OF THE PROFILE (iOS glassRow, «the profile wears the player's dress»): the glyph on its own round glass 56, the words on
 *  the long glass beside it, 10 apart. */
function GlassRow({ glyph, label, onClick, children, law }) {
  return (
    <button className="glass-row" aria-label={label} onClick={onClick} {...law?.props}>
      <span className="glass-row-mark">{glyph}</span>
      <span className="glass-row-plate">{children}</span>
      {law?.mark}
    </button>
  );
}
const Empty = ({ icon, word }) => (
  <div className="pane-empty"><span className="pane-empty-icon">{icon}</span><span>{t(word)}</span></div>
);
const ICONS = {
  wall: <svg width="42" height="42" viewBox="0 0 24 24"><rect x="3.5" y="3.5" width="17" height="10" rx="2" fill="none" stroke="currentColor" strokeWidth="1.5" /><path d="M3.5 17.5h17M3.5 20.5h11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" /></svg>,
  transactions: <svg width="42" height="42" viewBox="0 0 24 24"><path d="M4 8h15l-3.5-3.5M20 16H5l3.5 3.5" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" /></svg>,
  media: <Glyph name="photo" size={42} color="currentColor" />,
  video: <Glyph name="video" size={42} color="currentColor" />,
  files: <Glyph name="doc" size={42} color="currentColor" />,
  links: <Glyph name="link" size={42} color="currentColor" />,
  music: <Glyph name="musicNote" size={42} color="currentColor" />,
  voice: <Glyph name="mic" size={42} color="currentColor" />,
};

/** A picture or a film of the chat in its tile (iOS MTCover, VideoGridThumb): a third of the width, 120 tall; the film with its play. */
function Tile({ f, law }) {
  const url = useFile(f.mid, f.file && f.m.k === "img", f.m.e);
  const th = f.m.th ? `data:image/jpeg;base64,${f.m.th}` : null;
  return (
    <button className="pane-tile" aria-label={t(f.m.k === "vid" ? "Video" : "Photo")} {...law.props}>
      {(url || th) && <img src={url || th} alt="" draggable={false} />}
      {f.m.k === "vid" && <span className="post-tile-play" aria-hidden="true"><svg width="28" height="28" viewBox="0 0 30 30"><circle cx="15" cy="15" r="15" fill="rgba(255,255,255,0.9)" /><path d="M12 9.5v11l9-5.5z" fill="rgba(0,0,0,0.75)" /></svg></span>}
      {law.mark}
    </button>
  );
}
/** THE CHAT'S PICTURE OR FILM OPENED (iOS PhotoPresenter, VideoPresenter): on black, fitted to the window, the cross over it. */
function Shown({ f, onClose }) {
  const url = useFile(f.mid, f.file, f.m.e, f.m.sz > BIG);
  useLeave(onClose);
  return (
    <div className="media-show" role="dialog" aria-label={t(f.m.k === "vid" ? "Video" : "Photo")}>
      <div className="media-show-stage">
        {f.m.k === "vid" ? (url && <video src={url} controls autoPlay playsInline />) : url && <img src={url} alt="" draggable={false} />}
        {!url && (f.file ? <span className="spinner" /> : <span className="row-caption">{t("Not received")}</span>)}
      </div>
      <button className="glass-mark media-show-close" onClick={onClose} aria-label={t("Close")}><Glyph name="close" size={18} color="#fff" /></button>
    </div>
  );
}
/** A track or a voice of the chat in the one player (iOS musicList, voiceList): the play turns to the pause while it plays there; a
 *  track plays with the pane's tracks as the queue, a voice with this chat's voices behind it in feed order. */
function Sound({ f, title, side, playing, onPlay, law }) {
  return (
    <GlassRow label={title} law={law(() => (f.file ? onPlay() : invoke("media_want", { mid: f.mid })))}
              glyph={<Glyph name={playing ? "pauseFill" : "playFill"} size={18} color="var(--bar-glyph)" />}>
      <span className="glass-row-words"><span className="glass-row-title">{title}</span><span className="row-caption">{side}</span></span>
      <span className="glass-row-time">{hourOf(f.at)}</span>
    </GlassRow>
  );
}

/** The links a letter carries (iOS MTLinks.urls): the web's and Montana's own -- a game's letter is the board's card, not a link
 *  (iOS MTChessLetter.link). */
const linksIn = (text) => (String(text || "").match(/(?:https?|montana):\/\/[^\s<>"]+/gi) || [])
  .map((u) => u.replace(/[.,;:!?)\]}»'…]+$/, "")).filter((u) => !/^montana:\/\/chess/i.test(u));
const hostOf = (u) => { try { return new URL(u).host || u; } catch { return u; } };

/** THE PANES THEMSELVES: the strip, then the chosen pane; a quick stroke to the side over them turns to the next or the one before
 *  (iOS MTSwipePanes) -- here the touchpad's sideways stroke or a finger's. */
export function PeerPanes({ chat, name, myName, onShowLetter, onForward }) {
  const [tab, setTab] = useState("wall");
  const [files, setFiles] = useState(null);
  const [letters, setLetters] = useState(null);
  const [moves, setMoves] = useState(null);
  const [shown, setShown] = useState(null);
  const now = player.usePlayer();
  const [picking, setPicking] = useState(null);   // the chosen letters (iOS selecting, selected)
  const [menu, setMenu] = useState(null);         // a held item's menu (iOS openMenu)
  const turned = useRef(0);
  const swipe = useRef(null);
  const readFiles = () => invoke("media_list").then((all) => setFiles((all || []).filter((f) => f.chat === chat))).catch(() => setFiles([]));
  const readLetters = () => invoke("chat_open", { chat }).then((c) => setLetters(c?.msgs || [])).catch(() => setLetters([]));
  useEffect(() => {
    if (["media", "video", "files", "music", "voice"].includes(tab) && files == null) readFiles();
    if (tab === "links" && letters == null) readLetters();
    if (tab === "transactions" && moves == null) invoke("coin_moves_all").then((all) => setMoves((all || []).filter((m) => m.peer === chat))).catch(() => setMoves([]));
    invoke("trace", { line: `peer pane ${tab}` }).catch(() => {});
  }, [tab]);
  const keys = TABS.map(([k]) => k);
  const turn = (step) => {
    const now = Date.now();
    if (now - turned.current < 450) return;
    turned.current = now;
    const i = keys.indexOf(tab) + step;
    if (i >= 0 && i < keys.length) setTab(keys[i]);
  };
  /** THE ITEM LAW (iOS MTProfileItem, one law for every pane of the chat's things): a click opens, a hold -- the finger's long press or
   *  the mouse's right button -- opens the letter's menu, and while choosing a click takes the item in or out, its mark in the corner. */
  const flip = (mid) => setPicking((p) => { const n = new Set(p); if (n.has(mid)) n.delete(mid); else n.add(mid); return n; });
  const lawOf = (mid) => (open) => ({
    props: {
      onClick: () => (picking ? flip(mid) : open()),
      onContextMenu: (e) => {
        e.preventDefault();
        setMenu({ mid, x: Math.min(e.clientX, window.innerWidth - 250), y: Math.min(e.clientY, window.innerHeight - 230), confirm: false });
      },
      "aria-pressed": picking ? picking.has(mid) : undefined,
    },
    mark: picking && <span className={"pane-pick" + (picking.has(mid) ? " on" : "")} aria-hidden="true">{picking.has(mid) ? "✓" : ""}</span>,
  });
  const forget = async (mids) => {
    await invoke("chat_delete", { chat, mids, everyone: false }).catch(() => {});   // iOS deleteLocally: for me
    readFiles(); readLetters();
  };
  // THE PROFILE'S ROWS OF THE LETTER'S MENU (iOS MessageContextOverlay with onShowInChat): show it in the chat, forward it, delete it
  // here, choose it
  const deed = (what) => {
    const { mid } = menu;
    setMenu(null);
    if (what === "show") onShowLetter?.(mid);
    if (what === "forward") onForward?.([mid]);
    if (what === "select") setPicking(new Set([mid]));
    if (what === "mine") forget([mid]);
  };
  const inOrder = () => {
    const at = new Map([...(files || []).map((f) => [f.mid, f.at]), ...(letters || []).map((m) => [m.mid, m.at])]);
    return [...picking].sort((a, b) => (at.get(a) || 0) - (at.get(b) || 0));
  };
  const [, title, empty] = TABS.find(([k]) => k === tab);
  const icon = ICONS[tab];
  let body = null;
  if (tab === "wall") body = <Wall wall={chat} name={name} bare />;
  else if (tab === "transactions") {
    const days = moves ? foldHistory(moves) : [];
    body = !moves ? <div className="pane-wait"><span className="spinner" /></div> : !days.length ? <Empty icon={icon} word={empty} /> : days.map((d) => (
      <div key={d.day} className="pane-day">
        <div className="pane-day-head">{dayLabel(d.day)}</div>
        {d.lines.map((l) => (
          <GlassRow key={l.id} label={`${l.category}: ${(l.signed > 0 ? "+" : "") + coinCount(l.signed)}`}
                    onClick={() => l.tx && invoke("open_link", { url: "https://montana.xxx/explorer/#tx=" + l.tx }).catch(() => {})}
                    glyph={<span className="glass-row-sign" aria-hidden="true">{KIND_GLYPH[l.k] || "•"}</span>}>
            <span className="glass-row-words"><span className="glass-row-title">{l.category}</span><span className="row-caption">{hourOf(l.at * 1000)}</span></span>
            <span className="glass-row-sum digits" style={{ color: l.signed > 0 ? "var(--green)" : "#fff" }}>{(l.signed > 0 ? "+" : "") + coinCount(l.signed)}</span>
          </GlassRow>
        ))}
      </div>
    ));
  } else if (tab === "links") {
    const rows = (letters || []).flatMap((m) => linksIn(m.text).map((u, i) => ({ id: `${m.mid}:${i}`, mid: m.mid, u, at: m.at })));
    body = letters == null ? <div className="pane-wait"><span className="spinner" /></div> : !rows.length ? <Empty icon={icon} word={empty} /> : byDay(rows, (x) => x.at).map((d) => (
      <div key={d.day} className="pane-day">
        <div className="pane-day-head">{d.day}</div>
        {d.items.map((x) => (
          <GlassRow key={x.id} label={x.u} glyph={<Glyph name="link" size={18} color="var(--bar-glyph)" />}
                    law={lawOf(x.mid)(() => (/^montana:/i.test(x.u) ? window.dispatchEvent(new CustomEvent("montana-wall-link", { detail: x.u })) : invoke("open_link", { url: x.u })))}>
            <span className="glass-row-words"><span className="glass-row-title">{hostOf(x.u)}</span><span className="row-caption glass-row-link">{x.u}</span></span>
            <span className="glass-row-time">{hourOf(x.at)}</span>
          </GlassRow>
        ))}
      </div>
    ));
  } else {
    const pick = { media: (f) => f.m.k === "img", video: (f) => f.m.k === "vid", files: (f) => f.m.k === "doc" && !isMusic(f) && !GIF_NAME.test(f.m.n || ""),
                   music: isMusic, voice: (f) => f.m.k === "aud" }[tab];
    const items = (files || []).filter(pick);
    // the pane's tracks, newest first as they stand, are the queue; the voices go in feed order -- auto-next walks forward
    const asItem = (f) => ({ file: f.mid, mid: f.mid, ext: f.m.e, big: f.m.sz > BIG, chat, title: stem(f.m.n) || t("Track"),
                             sender: f.mine ? myName || "" : chatName(name) });
    const tracks = tab === "music" ? [...items].sort((a, b) => b.at - a.at).filter((f) => f.file).map(asItem) : [];
    const voices = tab === "voice" ? [...items].sort((a, b) => a.at - b.at).filter((f) => f.file).map(asItem) : [];
    const hear = (f) => {
      if (now.file === f.mid) return player.toggle();
      if (tab === "music") return player.playQueue(tracks, tracks.findIndex((x) => x.file === f.mid));
      const v = asItem(f);
      player.playVoice(v, voices, chat, v.sender);
    };
    body = files == null ? <div className="pane-wait"><span className="spinner" /></div> : !items.length ? <Empty icon={icon} word={empty} /> : byDay(items, (f) => f.at).map((d) => (
      <div key={d.day} className="pane-day">
        <div className="pane-day-head">{d.day}</div>
        {tab === "media" || tab === "video" ? (
          <div className="pane-tiles">{d.items.map((f) => <Tile key={f.mid} f={f} law={lawOf(f.mid)(() => setShown(f))} />)}</div>
        ) : tab === "files" ? d.items.map((f) => (
          <GlassRow key={f.mid} label={f.m.n || t("File")} glyph={<Glyph name="doc" size={18} color="var(--bar-glyph)" />}
                    law={lawOf(f.mid)(() => (f.file || f.mine ? invoke("media_open", { chat, mid: f.mid }) : invoke("media_want", { mid: f.mid })))}>
            <span className="glass-row-words"><span className="glass-row-title">{f.m.n || t("File")}</span><span className="row-caption">{sizeText(f.m.sz)}</span></span>
            <span className="glass-row-time">{hourOf(f.at)}</span>
          </GlassRow>
        )) : d.items.map((f) => (
          <Sound key={f.mid} f={f} law={lawOf(f.mid)} playing={now.file === f.mid && !now.paused} onPlay={() => hear(f)}
                 title={tab === "voice" ? t("Voice message") : (f.m.n || "").replace(/\.[^.]+$/, "") || t("Track")}
                 side={tab === "voice" ? (f.m.du ? `${Math.floor(f.m.du / 60)}:${String(Math.round(f.m.du % 60)).padStart(2, "0")}` : "") : sizeText(f.m.sz)} />
        ))}
      </div>
    ));
  }
  return (
    <section className={"peer-panes" + (picking ? " picking" : "")} aria-label={t(title)}
             onWheel={(e) => { if (Math.abs(e.deltaX) > 30 && Math.abs(e.deltaX) > 2 * Math.abs(e.deltaY)) turn(e.deltaX > 0 ? 1 : -1); }}
             onPointerDown={(e) => { if (e.pointerType !== "mouse") swipe.current = { x: e.clientX, y: e.clientY }; }}
             onPointerUp={(e) => {
               const s = swipe.current; swipe.current = null;
               if (s && Math.abs(e.clientX - s.x) > 60 && Math.abs(e.clientY - s.y) < 40) turn(e.clientX < s.x ? 1 : -1);
             }}>
      <TabStrip tabs={TABS} tab={tab} onTab={(k) => { setTab(k); setPicking(null); }} />
      <div className="pane-body">{body}</div>
      {/* a picture of the page opens among the chat's pictures, oldest first (iOS openPicture -> PhotoPresenter.present(_:among:)); a
          film keeps its player */}
      {shown && shown.m.k === "img" && shown.file ? (() => {
        const shots = (files || []).filter((x) => x.m.k === "img" && x.file).sort((a, b) => a.at - b.at);
        const pages = shots.map((x) => ({ key: x.mid, cover: x.m.th ? `data:image/jpeg;base64,${x.m.th}` : undefined,
                                          load: () => urlOf({ mid: x.mid, ext: x.m.e, big: x.m.sz > BIG }) }));
        return <PhotoAlbum pages={pages} start={Math.max(0, pages.findIndex((p) => p.key === shown.mid))} onClose={() => setShown(null)} />;
      })() : shown && <Shown f={shown} onClose={() => setShown(null)} />}
      {/* THE SELECTION BAR (iOS selectionBar): the cross, the count, forward through the chat's own picker, delete for me */}
      {picking && (
        <div className="pane-select-bar" style={{ bottom: now.file ? 52 : 0 }}>
          <button className="glass-mark" onClick={() => setPicking(null)} aria-label={t("Cancel")}><Glyph name="close" size={17} color="var(--bar-glyph)" /></button>
          <span className="pane-select-count digits">{picking.size}</span>
          <button className="pane-select-tool" disabled={!picking.size} aria-label={t("Forward")}
                  onClick={() => { const mids = inOrder(); setPicking(null); onForward?.(mids); }}><ForwardGlyph size={20} color={picking.size ? "var(--blue)" : "var(--gray)"} /></button>
          <button className="pane-select-tool" disabled={!picking.size} aria-label={t("Delete")}
                  onClick={() => { const mids = inOrder(); setPicking(null); forget(mids); }}><Glyph name="trash" size={20} color={picking.size ? "var(--red)" : "var(--gray)"} /></button>
        </div>
      )}
      {menu && (
        <div className="menu-shade" onClick={() => setMenu(null)} onContextMenu={(e) => { e.preventDefault(); setMenu(null); }}>
          <div className="letter-menu" style={{ left: menu.x, top: menu.y }} onClick={(e) => e.stopPropagation()} role="menu">
            <div className="menu-rows">
              {menu.confirm ? (
                <>
                  <div className="menu-ask">{t("Delete message?")}</div>
                  <MenuRow icon="trash" label={t("Delete for me")} red onClick={() => deed("mine")} />
                  <MenuRow icon="close" label={t("Cancel")} onClick={() => setMenu({ ...menu, confirm: false })} />
                </>
              ) : (
                <>
                  <MenuRow icon="chats" label={t("Show in chat")} onClick={() => deed("show")} />
                  <MenuRow icon="forward" label={t("Forward")} onClick={() => deed("forward")} />
                  <MenuRow icon="trash" label={t("Delete")} red onClick={() => setMenu({ ...menu, confirm: true })} />
                  <MenuRow icon="checkCircle" label={t("Select")} onClick={() => deed("select")} />
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
