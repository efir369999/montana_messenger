import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { t, locale, mtSize } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { Page, Section, Row, SHEET_GROUND } from "./Settings.jsx";
import { SAVED, chatName, rowTime } from "./Chats.jsx";
import { drawableUrl, sizeText } from "./Media.jsx";
import { CORE_SAID } from "./Wallet.jsx";
import { MintCoin } from "./Coin.jsx";
import { Linked } from "./Conversation.jsx";
import { ReportPage } from "./Safety.jsx";
import { held, MediaShow, PageTracks, POST_FILES, PostMedia, postKind, smallFace } from "./WallMedia.jsx";
import { wallTracks } from "./player.js";
import timeSend from "./assets/ios/time_send.png";
import writeOnWall from "./assets/ios/Montana_WriteOnWall_1024_Transparent.png";

/** THE WALL (iOS MTBoard / MTWallView): on a person's page the people they allow write posts -- words and pictures -- with
 *  likes, comments and views under each; my wall stands on my page, a correspondent's on theirs, as its owner last sent it. The
 *  words ride the pipe as «WL:», the files as sealed pieces on the node's blind store (Rust: board.rs). */

/** The post's own small marks (iOS: heart, bubble, eye), drawn here: the shipped glyphs have none of them. */
function Mark({ kind, on }) {
  const d = { heart: "M12 20.5s-7.5-4.6-7.5-10A4.3 4.3 0 0 1 12 7.4a4.3 4.3 0 0 1 7.5 3.1c0 5.4-7.5 10-7.5 10z",
              bubble: "M4 5.5h16v10H9l-5 4z", eye: "M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6zM12 9.3a2.7 2.7 0 1 0 0 5.4 2.7 2.7 0 0 0 0-5.4z",
              eyeOff: "M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6zM12 9.3a2.7 2.7 0 1 0 0 5.4 2.7 2.7 0 0 0 0-5.4zM4 4l16 16" }[kind];
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true">
      <path d={d} fill={on ? "#ff453a" : "none"} stroke={on ? "#ff453a" : "rgb(204,204,204)"} strokeWidth="1.7" strokeLinejoin="round" />
    </svg>
  );
}

/** THE GEMATRIA OF A SEAL (iOS MTBoard.gematria): the hex number read in base 29, each digit counted as its prime. */
const PRIMES = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109];
export function gematria(hex) {
  if (!hex) return PRIMES[0];
  if (!/^[0-9a-fA-F]+$/.test(hex)) return 0;
  let n = BigInt("0x" + hex), total = 0;
  do { total += PRIMES[Number(n % 29n)]; n /= 29n; } while (n > 0n);
  return total;
}
/** A moment on this machine's clock, to the millisecond (iOS MTBoard.local): 02.10.2026 13:05:07.624. */
export function localStamp(at) {
  const d = new Date(Math.round(at * 1000)), p = (x, k = 2) => String(x).padStart(k, "0");
  return `${p(d.getDate())}.${p(d.getMonth() + 1)}.${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`;
}
/** A comment's number in its chain, its moment, then its gematria (iOS MTBoard.numberLine, never translated): «313 · 02.10.2026
 *  13:05:07.624 · gematria 1234». */
const numberLine = (n, c) => `${n} · ${localStamp(c.at)}` + (c.h ? ` · gematria ${gematria(c.h)}` : "");

/** A comment's seal as the chain page lists it (iOS MTBoard.sealLine): its moment, the heads of its seal and of the one before,
 *  its gematria. */
const sealLine = (c) => `${localStamp(c.at)} · ${(c.h || "").slice(0, 16)} · ${(c.pv || "").slice(0, 16)} · gematria ${gematria(c.h || "")}`;

/** THE POST'S TIMECHAIN (iOS MTBoardChainPage): the span its comments cover and every seal of their chain; the windows the
 *  protocol core's pulse lived, each with the share it gives a right to, or the core's reason it says none. */
function PostChain({ post, onClose }) {
  const cs = post.comments || [];
  const [core, setCore] = useState(null);
  useEffect(() => { invoke("protocol_core").then(setCore).catch(() => setCore({ absent: "refused" })); }, []);
  return (
    <Page title="TimeChain" onClose={onClose} back>
      <Section head="TimeChain">
        {cs.length === 0 && <div className="post-note">{t("No comments yet")}</div>}
        {cs.length > 0 && <div className="set-row mono" role="group" aria-label={`${localStamp(cs[0].at)} · ${localStamp(cs[cs.length - 1].at)}`}>{localStamp(cs[0].at)} · {localStamp(cs[cs.length - 1].at)}</div>}
        {cs.map((c) => <div key={c.id} className="set-row mono chain-seal">{c.h ? sealLine(c) : localStamp(c.at)}</div>)}
      </Section>
      <Section head={t("Participation")} foot={t("A right becomes a wallet note only after the core confirms its redemption.")}>
        {!core && <div className="post-note">{t("Reading the wallet…")}</div>}
        {core?.absent && <div className="post-note">{t(CORE_SAID[core.absent] || CORE_SAID.refused)}</div>}
        {core?.ok && core.ok.windows.length === 0 && <div className="post-note">{t("No confirmed window yet")}</div>}
        {core?.ok && core.ok.windows.map((w) => (
          <div key={w.id} className="set-row chain-window" role="group" aria-label={`${t("Window")}: ${w.id}`}>
            <span className="row-title">{t("Window")} {w.id}<br /><span className="vpn-row-sub">{t("Right to a share")}: {w.share} · {t("Redemption window")}: {w.acceptedIn}</span></span>
          </div>
        ))}
      </Section>
    </Page>
  );
}

/** The walls moved, or a few seconds passed: what the wall shows is read again. */
function useWall(read, deps) {
  useEffect(() => {
    let gone = false, stop = null;
    const look = () => { if (!gone) read(); };
    look();
    listen("montana://wall", look).then((u) => { if (gone) u(); else stop = u; });
    const tick = setInterval(look, 4000);
    return () => { gone = true; stop?.(); clearInterval(tick); };
  }, deps);
}


/** A writer's face in a post's byline (iOS MTBoardFace): the small face the post carries, else the black circle with the letter in
 *  gold; the rows' white rim. */
function BoardFace({ face, glyph, name, size = 36 }) {
  return (
    <span className="board-face" style={{ width: size, height: size, fontSize: size * 0.42 }} aria-hidden="true">
      {face ? <img src={`data:image/jpeg;base64,${face}`} alt="" /> : (glyph || Array.from((name || "?").trim())[0]?.toUpperCase() || "?")}
    </span>
  );
}
/** The byline's moment (iOS .dateTime.day().month().hour().minute()): «22 окт., 19:34». */
const bylineTime = (at) => new Date(at * 1000).toLocaleString(locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
/** A post's link (iOS MTBoard.linkPost(p, on:)): the short one by its wall owner's claimed name when the window was told it, else the
 *  long one; a comment's: the short post link and the comment's number in its chain, else the long comment link (linkComment). */
const postLink = (p) => p.link || `montana://wall/post/${p.id}`;
const commentLink = (p, n, c) => (postLink(p).startsWith("montana://wall/@") ? `${postLink(p)}/${n}` : `montana://wall/comment/${p.id}/${c.id}`);

/** A POST A LINK NAMED (iOS MTBoardComments.present(post:comment:)): its comments over the app, the post whole at their head, the
 *  comment the link names brought to the middle. */
export function PostPage({ wall, id, focus, onClose }) {
  const [st, setSt] = useState(null);
  const read = () => invoke("wall_state", { wall: wall || null }).then(setSt).catch(() => {});
  useWall(read, [wall, id]);
  const post = st?.posts.find((p) => p.id === id);
  useEffect(() => { if (post) invoke("trace", { line: `wall_link opens post comments=${post.comments.length}` }).catch(() => {}); }, [!!post]);
  if (!post) return null;
  return <Comments post={post} wall={wall || null} canComment={!wall || st.canWrite} onMoved={read} onClose={onClose} focus={focus} />;
}

/** THE ROAD FROM A WRITER'S NAME TO THEIR PAGE (iOS MTBoardOpen): "" -- My page, a correspondent's reference -- theirs; the page
 *  rises over the one it was opened from (App listens for «montana-person»). */
export const openPerson = (w) => window.dispatchEvent(new CustomEvent("montana-person", { detail: w === "" ? { me: true } : { ref: w } }));
/** Whether a writer's face and name open their page here: never the page the post already stands on (iOS MTBoardCell.opens). */
const opens = (w, wall, inFeed) => (w == null ? false : w === "" ? wall != null || inFeed : w !== wall || inFeed);

/** THE BYLINE (iOS MTBoardByline): the face 36, the name semibold with the minting coin and its window's share over the newest
 *  post, the moment under it; one target over its whole room when there is a page to open. */
function Byline({ post, wall, inFeed, minting, share }) {
  const name = chatName(post.shown || post.byName);
  const inner = (
    <>
      <BoardFace face={post.face} glyph={post.byGlyph} name={name} />
      <span className="post-who">
        <span className="post-name"><b>{name}</b>
          {minting && <><MintCoin side={22} spinning />{share != null && <span className="post-share digits">{share}</span>}</>}</span>
        <span className="post-time">{bylineTime(post.at)}</span>
      </span>
    </>
  );
  return opens(post.writer, wall, inFeed)
    ? <button className="post-byline" aria-label={name} onClick={(e) => { e.stopPropagation(); openPerson(post.writer); }}>{inner}</button>
    : <span className="post-byline">{inner}</span>;
}

/** THE WALL A REPOST CAME FROM IS A LINK (iOS MTBoardCell.reposted): «Репост со стены: имя», the name in the system's blue, the
 *  whole line opening that wall's page wherever this machine holds the post as itself; else the name it carried, a word. */
function Reposted({ post }) {
  const [head, tail] = t("Reposted from %@").split("%@");
  const name = chatName(post.sourceName || post.from);
  const words = <><PostMark kind="repost" color="var(--gray)" /><span>{head}<span className={post.source != null ? "post-link-name" : ""}>{name}</span>{tail}</span></>;
  return post.source != null
    ? <button className="post-repost row-caption" aria-label={`${head}${name}${tail}`} onClick={(e) => { e.stopPropagation(); openPerson(post.source); }}>{words}</button>
    : <div className="post-repost row-caption">{words}</div>;
}

/** THE POST'S WORDS (iOS MTPostText): the body's own size, their links alive; in a list folded past the eighth line, «Показать
 *  полностью» and the chevron under -- a tap opens the post whole over its comments, where the words stand whole. */
function PostText({ text, whole }) {
  const box = useRef(null);
  const [folds, setFolds] = useState(false);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el || whole) return;
    const measure = () => setFolds(el.scrollHeight > el.clientHeight + 1);
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [text, whole]);
  return (
    <>
      <div ref={box} className={"post-text" + (whole ? "" : " fold")}><Linked text={text} /></div>
      {folds && <div className="post-unfold"><span>{t("Show in full")}</span><Glyph name="chevronRight" size={14} color="#fff" /></div>}
    </>
  );
}

/** WHERE A MENU STANDS (iOS: the platform's menu rises at its button, or at the finger for a hold): under the point -- its right edge
 *  on it for a button, its left for the finger -- 250 wide, held inside the window. */
const menuAt = (x, y, rows, fromButton = true) => {
  const w = 250, h = rows * 44 + 2;
  return { left: Math.max(8, Math.min(fromButton ? x - w : x, window.innerWidth - w - 8)), top: Math.max(8, Math.min(y + 4, window.innerHeight - h - 8)) };
};

/** The glyphs of the post's menu (iOS menuItems' systemImage), at the row's end as the platform's menu draws them. */
const MENU_MARKS = { Share: "share", Pin: "pin", Unpin: "pinSlash", Edit: "pencil", Copy: "copy", Report: "report", Delete: "trash" };
function MenuMark({ w }) {
  if (MENU_MARKS[w]) return <Glyph name={MENU_MARKS[w]} size={18} />;
  if (w === "Repost") return <PostMark kind="repost" />;
  if (w === "Save") return <PostMark kind="tray" />;
  if (w === "Remove from saved") return <PostMark kind="trayUp" />;
  return null;
}

/** The SF Symbols of a post's marks (iOS MTBoardCell.counters), drawn at their shapes. */
function PostMark({ kind, on, color }) {
  const c = color || "currentColor";
  const d = {
    heart: <path d="M12 20.5s-7.5-4.6-7.5-10A4.3 4.3 0 0 1 12 7.4a4.3 4.3 0 0 1 7.5 3.1c0 5.4-7.5 10-7.5 10z" fill={on ? c : "none"} stroke={c} strokeWidth="1.8" strokeLinejoin="round" />,
    bubble: <path d="M4 5.5h16v10H9l-5 4z" fill="none" stroke={c} strokeWidth="1.8" strokeLinejoin="round" />,
    tray: on ? <><path d="M3.5 13.5l2.5-8h12l2.5 8v5h-17z" fill={c} /><path d="M3.5 13.5h5l1.2 2h4.6l1.2-2h5" fill="none" stroke="#1c1c1e" strokeWidth="1.6" /></>
      : <><path d="M3.5 13.5l2.5-8h12l2.5 8v5h-17z" fill="none" stroke={c} strokeWidth="1.8" strokeLinejoin="round" /><path d="M3.5 13.5h5l1.2 2h4.6l1.2-2h5M12 6v6M9.5 9.5L12 12l2.5-2.5" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round" /></>,
    trayUp: <><path d="M3.5 13.5l2.5-8h12l2.5 8v5h-17z" fill="none" stroke={c} strokeWidth="1.8" strokeLinejoin="round" /><path d="M3.5 13.5h5l1.2 2h4.6l1.2-2h5M12 12V6M9.5 8.5L12 6l2.5 2.5" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round" /></>,
    repost: <path d="M7 7h11l-3-3M17 17H6l3 3M18 7v5M6 17v-5" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />,
    download: <><circle cx="12" cy="12" r="9" fill="none" stroke={c} strokeWidth="1.6" /><path d="M12 7.5v8M8.5 12.5L12 16l3.5-3.5" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" /></>,
    eye: <path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6zM12 9.3a2.7 2.7 0 1 0 0 5.4 2.7 2.7 0 0 0 0-5.4z" fill="none" stroke={c} strokeWidth="1.6" />,
    pin: <path d="M9 3h6l-1 6 3 3H7l3-3zM12 12v8" fill={c} stroke={c} strokeWidth="1.4" strokeLinejoin="round" />,
  }[kind];
  return <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true">{d}</svg>;
}

/** ONE POST (iOS MTBoardCell, plateBody): on the plate of a peer's bubble without its tail, 12 points in and 10 between -- the
 *  byline (the face, the name, the moment; the minting coin over the newest), the repost's line, the words, the files, the marks:
 *  likes, comments, keepers, reposts, the coins on it; the downloads and the views in the corner. The post's menu: Share, Pin, Edit,
 *  Save / Remove from saved, Repost, Copy, Report, Delete. A tap on the post opens its comments. */
export function PostCard({ post, wall, canComment, onMoved, inFeed, minting, share }) {
  const [menu, setMenu] = useState(false);
  const [thread, setThread] = useState(false);
  const [editing, setEditing] = useState(null);
  const [coinMenu, setCoinMenu] = useState(false);
  const [refused, setRefused] = useState(false);
  const [busy, setBusy] = useState(false);
  const [reporting, setReporting] = useState(false);
  const [show, setShow] = useState(null);   // the post's picture or film open in the viewer (iOS MTBoardMediaPage)
  const seen = useRef(false);
  const act = (a, extra = {}) => invoke("wall_do", { act: a, wall, id: post.id, ...extra }).then((ok) => { onMoved?.(); return ok; }).catch(() => false);
  useEffect(() => {
    if (wall && !seen.current && !post.mine) { seen.current = true; invoke("wall_do", { act: "view", wall, id: post.id }).catch(() => {}); }
  }, [wall, post.id]);
  // SAVE AND REPOST BRING THE FILES FIRST (iOS keep / repost): every file of the post comes to this machine, then the word goes
  const fetchAll = async () => { for (let i = 0; i < (post.media || []).length; i++) await invoke("wall_file", { wall, id: post.id, index: i, touch: true }); };
  const keepIt = async () => { setBusy(true); try { await fetchAll(); await act("keep"); } finally { setBusy(false); } };
  const repostIt = async () => { setBusy(true); try { await fetchAll(); await act("repost"); } finally { setBusy(false); } };
  const give = async (c) => { setCoinMenu(false); if (!(await act("coin", { text: String(c) }))) setRefused(true); };
  const items = [
    ["Share", () => invoke("share_text", { title: chatName(post.byName), text: (post.text || "").slice(0, 160), link: postLink(post) })],
    !wall && [post.pinned ? "Unpin" : "Pin", () => act("pin")],
    !wall && post.mine && !post.from && ["Edit", () => setEditing(post.text || "")],
    post.kept ? ((!post.mine || !wall) && ["Remove from saved", () => act("unkeep")]) : ["Save", keepIt],
    wall && !post.reposted && !post.mine && ["Repost", repostIt],
    post.text && ["Copy", () => invoke("copy_text", { text: post.text })],
    // ANOTHER PERSON'S POST MAY BE REPORTED FROM ITS MENU (iOS onReport, Guideline 1.2)
    !post.mine && ["Report", () => setReporting(true), true],
    !wall && ["Delete", () => act("remove"), true],
  ].filter(Boolean);
  if (thread) return <Comments post={post} wall={wall} canComment={canComment} onMoved={onMoved} onClose={() => setThread(false)} />;
  if (reporting) {
    // its writer when this machine knows them, and then they may be blocked with it; else the wall that carried it, nobody blocked
    const known = post.writer != null && post.writer !== "";
    return <ReportPage chat={known ? post.writer : wall || ""} who={chatName(post.byName)} blocks={known}
                       letter={{ mid: post.id, text: post.text || "" }} onClose={() => setReporting(false)} />;
  }
  if (editing !== null) {
    return (
      <Page title={t("Edit")} onClose={() => setEditing(null)}
            right={<button className="glass-mark" aria-label={t("Done")} onClick={async () => { await act("edit", { text: editing }); setEditing(null); }}><Glyph name="tick" size={18} color="#fff" /></button>}>
        <Section><textarea className="set-field post-field" rows={8} value={editing} aria-label={t("Edit")} onChange={(e) => setEditing(e.target.value)} /></Section>
      </Page>
    );
  }
  const marks = (kind, n, label, on, color, onClick) => (
    <button className="post-mark" aria-label={`${t(label)} ${n}`} aria-pressed={on || undefined} onClick={(e) => { e.stopPropagation(); onClick?.(); }}
            style={{ color: on ? color : undefined }}>
      <PostMark kind={kind} on={on} color={on ? color : undefined} /><span className="digits">{n}</span>
    </button>
  );
  return (
    <article className="post" aria-label={`${t("Post")}: ${chatName(post.shown || post.byName)}`} onClick={() => setThread(true)}>
      <header className="post-head">
        <Byline post={post} wall={wall} inFeed={inFeed} minting={minting} share={share} />
        {post.pinned && <span className="post-pin" role="img" aria-label={t("Pinned")}><PostMark kind="pin" color="var(--gray)" /></span>}
        <button className="post-more" aria-label={t("More")}
                onClick={(e) => { e.stopPropagation(); const r = e.currentTarget.getBoundingClientRect(); setMenu(menu ? null : menuAt(r.right, r.bottom, items.length)); }}>
          <Glyph name="more" size={18} color="rgb(152,152,157)" /></button>
      </header>
      {menu && (
        <div className="menu-shade" onClick={(e) => { e.stopPropagation(); setMenu(null); }}>
          <div className="post-menu menu-rows" role="menu" style={menu} onClick={(e) => e.stopPropagation()}>
            {items.map(([w, f, red]) => (
              <button key={w} role="menuitem" className={"menu-row" + (red ? " red" : "")} onClick={() => { setMenu(null); f(); }}><span>{t(w)}</span><MenuMark w={w} /></button>
            ))}
          </div>
        </div>
      )}
      {post.from && <Reposted post={post} />}
      {post.text && <PostText text={post.text} />}
      <PostMedia wall={wall} post={post} onShow={setShow} />
      {show != null && <MediaShow wall={wall} post={post} start={show} onClose={() => setShow(null)} />}
      {busy && <progress className="post-busy" aria-label={t("Downloading")} />}
      <footer className="post-foot">
        {marks("heart", post.likes, "Like", post.liked, "var(--red)", () => act("like"))}
        {marks("bubble", post.commentCount, "Comments", false, null, () => setThread(true))}
        {marks("tray", post.keepers, "Keepers", post.kept, "var(--blue)", () => (post.kept ? act("unkeep") : keepIt()))}
        {marks("repost", post.reposts, "Repost", post.reposted, "var(--blue)", () => wall && !post.reposted && !post.mine && repostIt())}
        {/* THE COINS ON THE POST (iOS coinMark): a tap gives one, the menu five or ten; my own post shows only what came */}
        {(wall && !post.mine) || post.coins > 0 ? (
          <button className="post-mark" aria-label={wall && !post.mine ? t("Give a coin") : `${t("Coins")} ${post.coins || 0}`}
                  onClick={(e) => { e.stopPropagation(); if (wall && !post.mine) give(1); }}
                  onContextMenu={(e) => { e.preventDefault(); e.stopPropagation(); if (wall && !post.mine) setCoinMenu(menuAt(e.clientX, e.clientY, 3, false)); }}>
            <MintCoin side={16} /><span className="digits">{post.coins || 0}</span>
          </button>
        ) : null}
        <span className="grow" />
        <span className="post-corner digits" role="img" aria-label={`${t("Downloads")} ${post.downloads || 0}`}><PostMark kind="download" />{post.downloads || 0}</span>
        {post.views != null && <span className="post-corner digits" role="img" aria-label={`${t("Views")} ${post.views}`}><PostMark kind="eye" />{compact(post.views)}</span>}
      </footer>
      {coinMenu && (
        <div className="menu-shade" onClick={(e) => { e.stopPropagation(); setCoinMenu(null); }}>
          <div className="menu-rows post-menu" role="menu" style={coinMenu} onClick={(e) => e.stopPropagation()}>
            {[1, 5, 10].map((c) => <button key={c} role="menuitem" className="menu-row" onClick={() => give(c)}><span>{`🪙 ${c}`}</span></button>)}
          </div>
        </div>
      )}
      {refused && (
        <div className="alert-shade" role="alertdialog" aria-label={t("Not enough coins")} onClick={(e) => e.stopPropagation()}>
          <div className="alert"><b>{t("Not enough coins")}</b><p>{t("Your coin balance is lower than this.")}</p>
            <div className="alert-keys"><button className="bold" onClick={() => setRefused(false)}>{t("OK")}</button></div></div>
        </div>
      )}
    </article>
  );
}

/** A count in the platform's short form past a thousand (iOS .number.notation(.compactName)). */
const compact = (n) => new Intl.NumberFormat(locale, { notation: "compact", maximumFractionDigits: 1 }).format(n || 0);

/** THE COMMENTS OF A POST (iOS MTBoardComments): the post whole at the head, the chain newest first -- each under its writer's
 *  byline, its words, «number · moment to the millisecond · gematria», on my own wall the eye that hides it from my visitors, its menu
 *  (Share, Copy, #number) -- and the field at the foot; TimeChain and Share in the bar. */
function Comments({ post, wall, canComment, onMoved, onClose, focus }) {
  const [typed, setTyped] = useState("");
  const [chain, setChain] = useState(false);
  const [menu, setMenu] = useState(null);
  // THE COMMENT A LINK NAMES stands in the middle when the page opens (iOS proxy.scrollTo(focus, anchor: .center))
  useEffect(() => { if (focus) document.getElementById(`cmt-${focus}`)?.scrollIntoView({ block: "center" }); }, [focus]);
  const act = (a, extra = {}) => invoke("wall_do", { act: a, wall, id: post.id, ...extra }).then(() => onMoved?.()).catch(() => {});
  // MY FACE OVER A COMMENT (iOS commentFace, 64): carried with the words
  const send = () => { const x = typed.trim(); if (!x) return; setTyped(""); smallFace(64).then((face) => act("comment", { text: x, face })); };
  if (chain) return <PostChain post={post} onClose={() => setChain(false)} />;
  const cs = post.comments.map((c, i) => ({ c, n: post.commentCount - post.comments.length + i + 1 })).reverse();
  // THE FIELD UNDER THE LIST (iOS: a bar of its own at the sheet's foot): the words, up to five lines, and the white send circle
  const foot = canComment ? (
    <div className="post-reply comments-foot">
      <textarea className="comments-field" rows={1} placeholder={t("Write a comment")} aria-label={t("Write a comment")} value={typed} maxLength={1000}
                onChange={(e) => setTyped(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); } }} />
      <button className="post-send" onClick={send} disabled={!typed.trim()} aria-label={t("Send")}>
        <svg width="30" height="30" viewBox="0 0 30 30" aria-hidden="true"><circle cx="15" cy="15" r="15" fill="#fff" /><path d="M15 21.5V9M9.8 14.2L15 9l5.2 5.2" fill="none" stroke="#000" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" /></svg>
      </button>
    </div>
  ) : <div className="post-note comments-foot comments-closed">{t("Only people who may write on this wall can comment")}</div>;
  return (
    <Page title={t("Comments")} onClose={onClose} ground={SHEET_GROUND} foot={foot}
          right={<span className="bar-marks">
            <button className="glass-mark" aria-label="TimeChain" onClick={() => setChain(true)}><svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" fill="none" stroke="rgb(204,204,204)" strokeWidth="1.8" /><path d="M12 7v5l3.5 2" fill="none" stroke="rgb(204,204,204)" strokeWidth="1.8" strokeLinecap="round" /></svg></button>
            <button className="glass-mark" aria-label={t("Share")} onClick={() => invoke("share_text", { title: chatName(post.byName), text: (post.text || "").slice(0, 160), link: postLink(post) })}>
              <Glyph name="share" size={18} color="var(--bar-glyph)" /></button></span>}>
      {/* ONE LIST (iOS MTBoardComments): the post whole as its first row, then the chain, newest first */}
      <Section>
        <div className="comments-post"><PostCardWhole post={post} wall={wall} /></div>
        {cs.length === 0 && <div className="set-row"><span className="row-title row-caption">{t("No comments yet")}</span></div>}
        {cs.map(({ c, n }) => (
          <div key={c.id} id={`cmt-${c.id}`} className={"post-comment" + (c.m ? " mine" : "") + (c.hid ? " hid" : "")}
               onContextMenu={(e) => { e.preventDefault(); setMenu({ c, n, at: menuAt(e.clientX, e.clientY, c.text ? 3 : 2, false) }); }}>
            <div className="post-comment-head">
              <BoardFace face={c.fc} glyph={c.glyph} name={c.by} />
              <span className="post-who"><span className="post-name"><b>{chatName(c.by)}</b></span><span className="post-time">{bylineTime(c.at)}</span></span>
            </div>
            {!(c.hid && !c.text) && <div className="post-comment-text"><Linked text={c.text} /></div>}
            <div className="post-comment-line">{numberLine(n, c)}</div>
            {!wall && (
              <button className="post-comment-eye" aria-pressed={!!c.hid} aria-label={t(c.hid ? "Show" : "Hide")}
                      onClick={() => act("hide", { text: c.id })}><Mark kind={c.hid ? "eye" : "eyeOff"} on={false} /></button>
            )}
          </div>
        ))}
      </Section>
      {menu && (
        <div className="menu-shade" onClick={() => setMenu(null)}>
          <div className="menu-rows post-menu" role="menu" style={menu.at} onClick={(e) => e.stopPropagation()}>
            <button role="menuitem" className="menu-row" onClick={() => { invoke("share_text", { title: chatName(menu.c.by), text: menu.c.text, link: commentLink(post, menu.n, menu.c) }); setMenu(null); }}><span>{t("Share")}</span><Glyph name="share" size={18} /></button>
            {menu.c.text && <button role="menuitem" className="menu-row" onClick={() => { invoke("copy_text", { text: menu.c.text }); setMenu(null); }}><span>{t("Copy")}</span><Glyph name="copy" size={18} /></button>}
            <button role="menuitem" className="menu-row" onClick={() => { invoke("copy_text", { text: String(menu.n) }); setMenu(null); }}><span>{`#${menu.n}`}</span><span className="menu-number" aria-hidden="true">#</span></button>
          </div>
        </div>
      )}
    </Page>
  );
}
/** The post whole over its comments (iOS whole: true): the byline, the words unfolded, the files -- read, not answered here. */
function PostCardWhole({ post, wall }) {
  const [show, setShow] = useState(null);
  return (
    <article className="post whole" aria-label={`${t("Post")}: ${chatName(post.shown || post.byName)}`}>
      <header className="post-head"><Byline post={post} wall={wall} /></header>
      {post.from && <Reposted post={post} />}
      {post.text && <PostText text={post.text} whole />}
      <PostMedia wall={wall} post={post} onShow={setShow} />
      {show != null && <MediaShow wall={wall} post={post} start={show} onClose={() => setShow(null)} />}
    </article>
  );
}

/** A picture's frame, its own shape whole -- or, past the shapes a post takes, its middle (iOS MTBoardFrame.own). */
function ownFrame(W, H) {
  const own = W / Math.max(1, H), a = held(own);
  const fw = a < own ? a / own : 1, fh = a < own ? 1 : own / a;
  return { a, x: (1 - fw) / 2, y: (1 - fh) / 2, w: fw, h: fh };
}
/** THE POSTER A POST CARRIES (iOS MTBoard.poster): the part its frame shows, the longest side 640, JPEG 0.6, the side shrinking by a
 *  fifth until its words fit 52 000 characters (or the side is down to 120). */
function posterOf(source, W, H, fr) {
  const cut = document.createElement("canvas");
  let side = 640;
  for (;;) {
    const k = Math.min(1, side / Math.max(W * fr.w, H * fr.h));
    cut.width = Math.max(1, Math.round(W * fr.w * k)); cut.height = Math.max(1, Math.round(H * fr.h * k));
    cut.getContext("2d").drawImage(source, W * fr.x, H * fr.y, W * fr.w, H * fr.h, 0, 0, cut.width, cut.height);
    const b64 = cut.toDataURL("image/jpeg", 0.6).split(",")[1] || "";
    if (b64.length <= 52000 || side <= 120) return b64;
    side = Math.round(side * 0.8);
  }
}
/** A film's first moment drawn, and its length (iOS MTBoardImage.upright for a video, MontanaAudioDuration). */
function filmOf(url) {
  return new Promise((ok) => {
    const v = document.createElement("video");
    const timer = setTimeout(() => ok(null), 8000);
    v.muted = true; v.preload = "auto"; v.src = url;
    v.onloadeddata = () => { v.currentTime = Math.min(0.1, (v.duration || 1) / 2); };
    v.onseeked = () => { clearTimeout(timer); ok(v); };
    v.onerror = () => { clearTimeout(timer); ok(null); };
  });
}
const lengthOf = (url) => new Promise((ok) => {
  const a = document.createElement("audio");
  const timer = setTimeout(() => ok(undefined), 6000);
  a.preload = "metadata"; a.src = url;
  a.onloadedmetadata = () => { clearTimeout(timer); ok(Number.isFinite(a.duration) && a.duration > 0 ? a.duration : undefined); };
  a.onerror = () => { clearTimeout(timer); ok(undefined); };
});

/** A FILE COMES INTO THE WALL'S DRAFT THE MOMENT IT IS PICKED (iOS MTBoardDrafts.take, the composer's load): its kind by its name, a
 *  picture's or a film's frame and poster, a track's or a film's length; its bytes kept in the media store under a draft's name. A
 *  picture of another format goes as the JPEG of its own pixels. */
async function takeFile(file) {
  const kind = postKind(file.name);
  let ext = (file.name.split(".").pop() || "").toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8);
  let bytes = null, thumb, fr, dur;
  if (kind === "img") {
    const url = await drawableUrl(file);
    try {
      const img = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = no; i.src = url; });
      const W = img.naturalWidth, H = img.naturalHeight;
      fr = ownFrame(W, H);
      thumb = posterOf(img, W, H, fr);
      if (!/^image\/(jpeg|png|gif|webp)$/.test(file.type)) {
        const full = document.createElement("canvas");
        full.width = W; full.height = H;
        full.getContext("2d").drawImage(img, 0, 0);
        bytes = new Uint8Array(await (await new Promise((ok) => full.toBlob(ok, "image/jpeg", 0.9))).arrayBuffer());
        ext = "jpg";
      }
    } finally { URL.revokeObjectURL(url); }
  } else if (kind === "vid" || kind === "aud") {
    const url = URL.createObjectURL(file);
    try {
      if (kind === "vid") {
        const v = await filmOf(url);
        if (v && v.videoWidth) {
          fr = ownFrame(v.videoWidth, v.videoHeight);
          thumb = posterOf(v, v.videoWidth, v.videoHeight, fr);
          if (Number.isFinite(v.duration) && v.duration > 0) dur = v.duration;
        }
      } else {
        dur = await lengthOf(url);
      }
    } finally { URL.revokeObjectURL(url); }
  }
  bytes = bytes || new Uint8Array(await file.arrayBuffer());
  const name = await invoke("wall_file_put", bytes);
  invoke("trace", { line: `post_pick kind=${kind} kb=${Math.round(bytes.length / 1024)}` }).catch(() => {});
  return { file: name, kind, name: file.name, ext: ext || "bin", size: bytes.length, thumb, fr, dur };
}

/** The post as it will stand, drawn from a draft (iOS MTBoardDraft.seen / MTBoard.fresh): mine, its files' posters for its tiles. */
const draftPost = (d, me) => ({ id: "draft", byName: me, byGlyph: Array.from(me || "?")[0] || "?", at: d.at || Date.now() / 1000, text: d.text,
  media: d.files.map((f) => ({ kind: f.kind, name: f.name, ext: f.ext, size: f.size, thumb: f.thumb, fr: f.fr, dur: f.dur })), mine: true,
  keepers: 1, likes: 0, downloads: 0, reposts: 0, comments: [], commentCount: 0, writer: null, shown: me });   // no road while it is written

/** A FILE OF THE POST BEING WRITTEN (iOS MTBoardComposer.attached): its miniature -- a picture's poster in its square, a track's or a
 *  file's glyph -- its name and size, and the cross that takes it off the post. */
function Attached({ f, onRemove }) {
  return (
    <div className="set-row attached" role="group" aria-label={f.name}>
      <span className="attached-mini">{f.thumb ? <img src={`data:image/jpeg;base64,${f.thumb}`} alt="" />
        : <Glyph name={f.kind === "aud" ? "musicNote" : "doc"} size={17} color="var(--gray)" />}</span>
      <span className="attached-words"><span className="attached-name">{f.name}</span><span className="row-caption">{sizeText(f.size)}</span></span>
      <button className="attached-cross" onClick={onRemove} aria-label={`${t("Remove")}: ${f.name}`}>
        <svg width="22" height="22" viewBox="0 0 22 22" aria-hidden="true"><circle cx="11" cy="11" r="11" fill="rgba(142,142,147,0.45)" /><path d="M7.5 7.5l7 7M14.5 7.5l-7 7" stroke="rgba(235,235,245,0.75)" strokeWidth="1.8" strokeLinecap="round" /></svg>
      </button>
    </div>
  );
}

/** THE BAR OF A POST ON ITS WAY (iOS MTBoardProgress): «Публикуется», the share and the bytes laid, the platform's line under them. */
function Laying({ at, failed }) {
  const share = at && at.total > 0 ? Math.min(1, at.done / at.total) : 0;
  return (
    <div className="laying" role="status" aria-label={t(failed ? "Could not post" : "Publishing")}>
      <div className="laying-head"><b>{t(failed ? "Could not post" : "Publishing")}</b>
        <span className="digits">{`${Math.floor(share * 100)}% · ${mtSize(at?.done)} of ${mtSize(at?.total)}`}</span></div>
      <progress value={share} max={1} />
    </div>
  );
}

/** A NEW POST (iOS MTBoardComposer): the post as it will stand -- the byline, the words a field in the post's own font, the pictures
 *  and films in their mosaic, the tracks and the files as rows -- then «Фото и видео» and «Треки и файлы» and the files picked, each
 *  with its cross. Every change is laid into the wall's draft at once (iOS lay): the cross keeps it, and the wall shows it until it
 *  is posted or thrown away. The TimeSend mark publishes: the bar of the files laid over the page, the page leaving when the post is
 *  out (iOS MTBoardProgress, publish). */
function Composer({ wall, onClose }) {
  const [d, setD] = useState(null);
  const [me, setMe] = useState("");
  const [taking, setTaking] = useState(0);
  const [laying, setLaying] = useState(null);
  const [failed, setFailed] = useState(false);
  const pics = useRef(null), docs = useRef(null), field = useRef(null);
  useEffect(() => {
    const blank = { text: "", files: [], at: Date.now() / 1000 };
    invoke("wall_draft", { wall }).then((x) => setD(x || blank)).catch(() => setD(blank));
    invoke("identity_state").then((s) => setMe(chatName(s?.name || ""))).catch(() => {});
    const off = listen("montana://wall-laid", (e) => setLaying(e.payload));
    return () => { off.then((u) => u()); };
  }, []);
  useEffect(() => { if (d) field.current?.focus(); }, [d == null]);
  if (!d) return null;
  // EVERY CHANGE IS LAID INTO THE WALL'S STORE (iOS lay): the words as they are typed, a file the moment it is picked or taken off
  const lay = (f) => setD((cur) => { const next = f(cur); invoke("wall_draft_set", { wall, draft: next }).catch(() => {}); return next; });
  const take = async (list) => {
    const picked = [...list].slice(0, Math.max(0, POST_FILES - d.files.length));
    setTaking((n) => n + picked.length);
    for (const file of picked) {
      try {
        const x = await takeFile(file);
        lay((cur) => ({ ...cur, files: [...cur.files, x].slice(0, POST_FILES) }));
      } catch { invoke("trace", { line: "post_pick none" }).catch(() => {}); }
      setTaking((n) => n - 1);
    }
  };
  const empty = !d.text.trim() && !d.files.length;
  const publish = async () => {
    if (laying || empty || taking) return;
    setFailed(false); setLaying({ done: 0, total: d.files.reduce((s, f) => s + (f.size || 0), 0) });
    try {
      const face = wall ? await smallFace(96) : null;
      await invoke("wall_post", { wall, text: d.text, files: d.files, face });
      onClose();
    } catch {
      setFailed(true);
    }
  };
  const post = draftPost(d, me);
  return (
    <Page title={t("New post")} onClose={onClose}
          right={!laying || failed ? (
            <button className="glass-mark publish-mark" onClick={publish} disabled={empty || taking > 0} aria-label={t("Publish")}>
              <img src={timeSend} alt="" /></button>) : null}>
      <input ref={pics} type="file" accept="image/*,video/mp4,video/quicktime,.mov,.m4v,.heic,.heif" multiple hidden
             onChange={(e) => { const l = [...e.target.files]; e.target.value = ""; take(l); }} />
      <input ref={docs} type="file" multiple hidden onChange={(e) => { const l = [...e.target.files]; e.target.value = ""; take(l); }} />
      {laying && <Laying at={laying} failed={failed} />}
      {/* THE PAGE SHOWS THE POST ONE TO ONE AS IT WILL BE PUBLISHED (iOS: the post's own cell, its words a field) */}
      <article className="post composing" onClick={() => field.current?.focus()}>
        <header className="post-head"><Byline post={post} wall={wall} /><span className="post-more" aria-hidden="true"><Glyph name="more" size={18} color="rgb(152,152,157)" /></span></header>
        <textarea ref={field} className="post-text post-text-field" rows={1} placeholder={t("Write something")} aria-label={t("Write something")}
                  value={d.text} maxLength={4000} disabled={!!laying && !failed} onChange={(e) => { const v = e.target.value; lay((cur) => ({ ...cur, text: v })); }} />
        <PostMedia wall={wall} post={post} draft />
      </article>
      {(!laying || failed) && (
        <Section>
          {/* the platform's own labels (iOS Label: «photo.on.rectangle», «music.note.list»), the page's one tint */}
          <button className="set-row pick-row" onClick={() => pics.current.click()}><Glyph name="photo" size={20} color="#fff" /><span className="row-title">{t("Photos and videos")}</span></button>
          <button className="set-row pick-row" onClick={() => docs.current.click()}><Glyph name="musicNote" size={20} color="#fff" /><span className="row-title">{t("Tracks and files")}</span></button>
        </Section>
      )}
      {(d.files.length > 0 || taking > 0) && (!laying || failed) && (
        <Section>
          {d.files.map((f) => <Attached key={f.file} f={f} onRemove={() => lay((cur) => ({ ...cur, files: cur.files.filter((x) => x.file !== f.file) }))} />)}
          {taking > 0 && <div className="set-row center" role="status" aria-label={t("Downloading")}><span className="spinner small" /></div>}
        </Section>
      )}
      {failed && <Section><div className="set-row"><span className="row-title red">{t("Could not post")}</span></div></Section>}
    </Page>
  );
}

/** A POST NOT YET PUBLISHED, ON ITS WALL (iOS MTBoardDraftCell): a plate that names it a draft -- the write picture 36, «Черновик», the
 *  trash -- over the post as it will stand; a touch on either opens the page that writes it, where it was left. */
function DraftCell({ wall, d, onOpen, onGone }) {
  const [me, setMe] = useState("");
  useEffect(() => { invoke("identity_state").then((s) => setMe(chatName(s?.name || ""))).catch(() => {}); }, []);
  return (
    <div className="draft-cell">
      <div className="draft-plate">
        <button className="draft-open" onClick={onOpen} aria-label={t("Draft")}><img src={writeOnWall} alt="" /><span>{t("Draft")}</span></button>
        <button className="draft-trash" onClick={async () => { await invoke("wall_draft_set", { wall, draft: null }); onGone(); }} aria-label={t("Delete")}>
          <Glyph name="trash" size={18} color="#fff" /></button>
      </div>
      <div className="draft-post" role="button" tabIndex={0} onClick={onOpen} aria-label={`${t("Draft")}: ${d.text.slice(0, 40)}`}>
        <article className="post composing" aria-hidden="true">
          <header className="post-head"><Byline post={draftPost(d, me)} wall={wall} /></header>
          {d.text && <PostText text={d.text} />}
          <PostMedia wall={wall} post={draftPost(d, me)} draft />
        </article>
      </div>
    </div>
  );
}

/** THE WALL'S WRITE BUTTON'S FACE (iOS MTBoardWriteFace): iOS's own picture WriteOnWall at 40, the words, on the plate's one-tone
 *  glass, 50 tall. */
function WriteFace({ onClick, words }) {
  return (
    <button className="write-face" onClick={onClick} aria-label={words}>
      <img src={writeOnWall} alt="" /><span>{words}</span>
    </button>
  );
}
/** The share of the minutes a post's comment window holds now (iOS MTBoard.window): unbroken by a silence of a minute, live while its
 *  last comment is younger than a minute. */
function windowShare(p) {
  const ats = (p.comments || []).map((c) => c.at).sort((a, b) => a - b);
  if (!ats.length) return null;
  const broken = ats.some((a, i) => i > 0 && a - ats[i - 1] >= 60);
  const now = Date.now() / 1000, live = now - ats[ats.length - 1] < 60 && !broken;
  return broken ? 0 : Math.max(1, Math.floor(((live ? now : ats[ats.length - 1]) - ats[0]) / 60));
}

/** A WALL ON A PAGE (iOS MTWallSection): mine, or a correspondent's («wall» is their chat); «Написать на стене» where I may. */
export function Wall({ wall, name }) {
  const [st, setSt] = useState(null);
  const [writing, setWriting] = useState(false);
  const [draft, setDraft] = useState(null);   // A DRAFT STANDS ON ITS WALL (iOS MTBoardDraftCell)
  const read = () => {
    invoke("wall_state", { wall: wall || null }).then(setSt).catch(() => {});
    invoke("wall_draft", { wall: wall || null }).then(setDraft).catch(() => {});
  };
  useWall(read, [wall]);
  if (writing) return <Composer wall={wall || null} onClose={() => { setWriting(false); read(); }} />;
  if (!st) return null;
  return (
    // no head of its own (iOS MTBoardRows): on my page the wall stands right under the face, on a person's page under the strip's «Стена»
    <section className="wall" aria-label={t(wall ? "Wall" : "My wall")}>
      {st.canWrite && (
        <WriteFace onClick={() => setWriting(true)} words={t("Write on the wall")} />
      )}
      {st.canWrite && draft && <DraftCell wall={wall || null} d={draft} onOpen={() => setWriting(true)} onGone={read} />}
      {wall && !st.held && <div className="post-note">{t("The wall comes when %@'s phone answers.").replace("%@", chatName(name || ""))}</div>}
      {(st.held || !wall) && st.posts.length === 0 && <div className="post-note">{t("No posts yet")}</div>}
      {/* THE COINS MINT OVER THE NEWEST (iOS minting): the post at the head of its wall wears the turning coin and its window's share */}
      <PageTracks.Provider value={wallTracks(st.posts.map((p) => ({ post: p, wall: wall || null })))}>
        {st.posts.map((p, i) => <PostCard key={p.id} post={p} wall={wall || null} canComment={!wall || st.canWrite} onMoved={read} minting={i === 0} share={i === 0 ? windowShare(p) : null} />)}
      </PageTracks.Provider>
    </section>
  );
}

/** A post's last moment (iOS MTBoard.lastAt): its own, or its newest comment's. */
const lastAt = (p) => Math.max(p.at, ...(p.comments || []).map((c) => c.at));
/** Every word a post carries -- its words, its writer's name, the wall it stands on, the wall it was taken from, its files' names,
 *  every comment and its writer -- and every word typed found among them, case aside (iOS MTWallFeed.matches). */
function matches(it, q) {
  if (!q) return true;
  const p = it.post;
  const all = [p.text, p.byName, p.shown, p.from, it.wall ? it.wallName : "", ...(p.media || []).map((m) => m.name),
               ...(p.comments || []).flatMap((c) => [c.by, c.text])].filter(Boolean).join("\n").toLocaleLowerCase();
  return q.split(/\s+/).filter(Boolean).every((w) => all.includes(w));
}

/** WHOSE WALL A POST STANDS ON, when its writer is not the wall's owner (iOS MTWallFeed.wallLink): «На стене: имя», the name in
 *  the system's blue, or «На вашей стене»; the whole line opens that page. */
function WallLink({ it }) {
  const [head, tail] = t("On %@'s wall").split("%@");
  const name = chatName(it.wallName);
  const said = it.wall ? `${head}${name}${tail}` : t("On your wall");
  return (
    <button className="wall-link row-caption" aria-label={said} onClick={() => openPerson(it.wall || "")}>
      <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="3.5" width="17" height="10" rx="2" fill="none" stroke="currentColor" strokeWidth="1.6" /><path d="M3.5 17.5h17M3.5 20.5h11" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" /></svg>
      {it.wall ? <span>{head}<span className="post-link-name">{name}</span>{tail}</span> : <span className="post-link-name">{said}</span>}
    </button>
  );
}

/** THE WALL OF THOUGHTS (iOS MTWallFeed): every post of my wall and of every wall of my people this machine holds, the newest first,
 *  searched by the list's own field; the minting coin over the post with the newest moment; the write in the page's corner as the
 *  chats' (iOS mtPageAction, «square.and.pencil»). The search is the list's first row and scrolls with the posts (iOS
 *  MontanaTimePanelList: «the list's first row is the search»). */
export function FeedPane({ query = "", head = null }) {
  const [items, setItems] = useState(null);
  const [writing, setWriting] = useState(false);
  const [draft, setDraft] = useState(null);
  const read = () => {
    invoke("wall_feed").then(setItems).catch(() => {});
    invoke("wall_draft", { wall: null }).then(setDraft).catch(() => {});
  };
  useWall(read, []);
  if (writing) return <Composer wall={null} onClose={() => { setWriting(false); read(); }} />;
  const q = query.trim().toLocaleLowerCase();
  const shown = (items || []).filter((it) => matches(it, q));
  const newest = shown.reduce((a, it) => (!a || lastAt(it.post) > lastAt(a.post) ? it : a), null);
  return (
    <>
      <div className="feed-pane" aria-label={t("Wall of Thoughts")}>
        {head}
        {/* MY OWN DRAFT STANDS FIRST (iOS MTWallFeed: the author's word 25.09), not under a search */}
        {!q && draft && <DraftCell wall={null} d={draft} onOpen={() => setWriting(true)} onGone={read} />}
        {items && shown.length === 0 && !(draft && !q) && <div className="feed-empty">{q ? t("Nothing found") : t("Posts on your people's walls\nwill appear here")}</div>}
        <PageTracks.Provider value={wallTracks(shown.map((it) => ({ post: it.post, wall: it.wall || null })))}>
          {shown.map((it) => (
            <div key={(it.wall || "me") + "/" + it.post.id} className="feed-cell">
              {it.post.own !== true && <WallLink it={it} />}
              <PostCard post={it.post} wall={it.wall || null} canComment={!it.wall || it.canWrite} onMoved={read} inFeed
                        minting={it === newest} share={it === newest ? windowShare(it.post) : null} />
            </div>
          ))}
        </PageTracks.Provider>
      </div>
      <button className="compose-door" onClick={() => setWriting(true)} aria-label={t("New post")}>
        <Glyph name="compose" size={22} color="#fff" />
      </button>
    </>
  );
}

const RULES = [["everyone", "Everyone"], ["onlyMe", "Only me"], ["some", "Some people"], ["except", "Everyone except"]];

/** WHO MAY WRITE ON MY WALL, AND WHO MAY SEE IT (iOS MTBoardRule): everyone, only me, some -- chosen -- or everyone but some.
 *  «Only contacts» is iOS's own: Windows keeps no contact book. */
export function WallRules({ onClose }) {
  const [r, setR] = useState(null);
  const [people, setPeople] = useState([]);
  const [act, setAct] = useState(null);
  const read = () => invoke("wall_rules").then(setR).catch(() => {});
  useEffect(() => { read(); invoke("chats").then((rows) => setPeople((rows || []).filter((x) => !x.group && !x.blocked && x.ref !== SAVED))).catch(() => {}); }, []);
  if (!r) return null;
  const put = async (a, next) => { await invoke("wall_rule_set", { act: a, rule: next }); read(); };
  if (act) {
    const cur = r[act];
    const list = cur.rule === "some" ? "allow" : "deny";
    return (
      <Page title={t(act === "see" ? "Who can see my wall" : "Who can write on my wall")} onClose={() => setAct(null)} back>
        <Section>
          <div className="slow-steps rule-steps" role="radiogroup" aria-label={t(act === "see" ? "Who can see my wall" : "Who can write on my wall")}>
            {RULES.map(([k, w]) => (
              <button key={k} role="radio" aria-checked={cur.rule === k} className={"slow-step" + (cur.rule === k ? " on" : "")}
                      onClick={() => put(act, { ...cur, rule: k })}>{t(w)}</button>
            ))}
          </div>
        </Section>
        {(cur.rule === "some" || cur.rule === "except") && (
          <Section head={t("Choose people")}>
            {people.map((p) => {
              const on = cur[list].includes(p.ref);
              return (
                <label key={p.ref} className="set-row toggle">
                  <span className="row-title">{chatName(p.name)}</span>
                  <input type="checkbox" role="switch" aria-label={chatName(p.name)} checked={on}
                         onChange={() => put(act, { ...cur, [list]: on ? cur[list].filter((x) => x !== p.ref) : [...cur[list], p.ref] })} />
                </label>
              );
            })}
          </Section>
        )}
      </Page>
    );
  }
  const word = (x) => t((RULES.find(([k]) => k === x.rule) || [0, "Everyone"])[1]);
  return (
    <Page title={t("Wall")} onClose={onClose} back>
      <Section>
        <Row title={t("Who can write on my wall")} value={word(r.write)} onClick={() => setAct("write")} />
        <Row title={t("Who can see my wall")} value={word(r.see)} onClick={() => setAct("see")} />
      </Section>
    </Page>
  );
}
