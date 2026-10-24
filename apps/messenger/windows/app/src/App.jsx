import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import TopBar, { Glyph, turnPanel, usePanelOpen } from "./TopBar.jsx";
import { CoinSpinner, PULL, pullAngle } from "./Coin.jsx";
import { ArchiveRow, ChatRow, EraseSheet, Face, MeetSheet, QRCard, RowMenu, SAVED, chatName, rowTime, useChanged } from "./Chats.jsx";
import { ALL, FolderEmpty, FoldersPage, FolderTabs, takes, useFolders } from "./Folders.jsx";
import { useLibrary } from "./Library.jsx";
import { useLeave } from "./leave.js";
import { Calls, Contacts, Drawer, Gallery, Music, NotYet } from "./Panes.jsx";
import { ChessPane } from "./Chess.jsx";
import Settings, { Page, KeepAsk, VERSION } from "./Settings.jsx";
import CardPane from "./Card.jsx";
import { PageGround } from "./Ground.jsx";
import { FeedPane, PostPage } from "./Wall.jsx";
import { WalletPage } from "./Wallet.jsx";
import VpnPane, { P2pPane } from "./Vpn.jsx";
import PasswordsPane from "./Passwords.jsx";
import { MyPage, PeerPage } from "./Profile.jsx";
import { BlockSheet } from "./Safety.jsx";
import { ChannelCreate, GroupCreate } from "./Groups.jsx";
import CallLayer from "./Call.jsx";
import RoomLayer from "./Room.jsx";

import Conversation from "./Conversation.jsx";
import { PlayerBar } from "./PlayerBar.jsx";
import * as player from "./player.js";
import Onboarding, { TermsGate, Welcome } from "./Onboarding.jsx";

// iOS Montana 2251's root (ContentView.swift 438-468): no seed -- the onboarding; a seed and terms not yet agreed -- the
// terms' gate; then the welcome for 0.6 s; then the app. In the app the time panel stands over the page under it, every
// page with the search row first; wide, the open chat stands beside the list; narrow, one column, as on the phone.
export default function App() {
  const [person, setPerson] = useState(null);   // identity_state: seated, name, callsign, terms_ok
  const [welcome, setWelcome] = useState(false);

  const look = () => invoke("identity_state").then(setPerson);
  useEffect(() => { look(); }, []);

  if (!person) return <div className="splash" />;
  if (!person.seated) return <Onboarding onDone={() => look()} />;
  if (!person.terms_ok) {
    return <TermsGate onAgree={async () => { await invoke("identity_accept_terms"); setWelcome(true); setTimeout(() => setWelcome(false), 600); look(); }} />;
  }
  if (welcome) return <Welcome />;
  return <Main person={person} onPerson={look} />;
}

function useNarrow() {
  const q = "(max-width: 700px)";
  const [narrow, setNarrow] = useState(() => window.matchMedia(q).matches);
  useEffect(() => {
    const m = window.matchMedia(q);
    const on = () => setNarrow(m.matches);
    m.addEventListener("change", on);
    return () => m.removeEventListener("change", on);
  }, []);
  return narrow;
}

const NOT_YET = { mesh: "Mesh wall" };

function lastMedia() {
  try { return localStorage.getItem("lastMediaPane") || "music"; } catch { return "music"; }
}

function Main({ person, onPerson }) {
  const [core, setCore] = useState(null);
  const [failed, setFailed] = useState(null);
  const [query, setQuery] = useState("");
  const [pane, setPane] = useState("chats");
  const [media, setMedia] = useState(lastMedia);   // the media slot: the last of music and gallery (iOS lastMediaPane)
  const [rows, setRows] = useState(null);
  const [open, setOpen] = useState(null);
  const [meeting, setMeeting] = useState(false);
  const [rowMenu, setRowMenu] = useState(null);   // {row, x, y}
  const [erasing, setErasing] = useState(null);
  const [drawer, setDrawer] = useState(false);
  const [parked, setParked] = useState([]);        // the persons of this computer waiting on the shelf (iOS MTSeats)
  const [moving, setMoving] = useState(false);     // a move between seats: the program starts again in the other folder
  const [over, setOver] = useState(null);          // the page over the app: "settings", "me", {peer}
  const [archive, setArchive] = useState(false);    // the archive's own list
  const [blocking, setBlocking] = useState(null);   // the row whose block is asked
  const [found, setFound] = useState([]);           // the letters the search found
  const [focus, setFocus] = useState(null);         // the letter the open chat goes to
  const [forward, setForward] = useState(null);     // the letters a page asked the chat to forward through its own picker
  const [composeMenu, setComposeMenu] = useState(false);
  const [newGroup, setNewGroup] = useState(false);
  const [newChannel, setNewChannel] = useState(false);
  const [qrFull, setQrFull] = useState(false);   // the screen of my code and my link (iOS MontanaQRFullView)
  // THE PAGES A WRITER'S NAME OPENED (iOS MTBoardRoute .mine / .person): each over the one it was opened from, back to it
  const [people, setPeople] = useState([]);
  useEffect(() => {
    // each page its own key: a page that leaves never hands its state (its way out) to the one opened after it
    let seq = 0;
    const f = (e) => setPeople((s) => [...s, { ...e.detail, key: ++seq }]);
    // A WALL'S LINK OPENS ITS POST (iOS MTBoardComments.open): the post and the comment it names among the posts this machine holds
    const link = (e) => invoke("wall_find", { link: e.detail }).then((hit) => { if (hit) setPeople((s) => [...s, { post: hit, key: ++seq }]); }).catch(() => {});
    window.addEventListener("montana-person", f);
    window.addEventListener("montana-wall-link", link);
    return () => { window.removeEventListener("montana-person", f); window.removeEventListener("montana-wall-link", link); };
  }, []);
  const narrow = useNarrow();
  const folders = useFolders();   // the tabs over the list (iOS MTChatFolders)
  // THE CHOSEN FOLDER IS ALL AT EVERY LAUNCH (iOS UIState.chatFolder, as the reference): the choice lives while the window does
  const [folder, setFolder] = useState(ALL);
  const tab = folders.find((f) => f.id === folder) || folders[0];
  const pick = (id) => { setFolder(id); setPane("chats"); };
  // THE BAR'S GLYPHS WEAR THE ICONS' STYLE (iOS MontanaOctagon.barGlyph): white with the white icons, the platform's grey otherwise
  const { style: iconStyle } = useLibrary();
  useEffect(() => { document.documentElement.dataset.icons = iconStyle; }, [iconStyle]);

  const look = () => invoke("chats").then(setRows);
  // THE MISSED CALLS' BADGE (iOS missedCallsUnseen): their missed calls since the calls page was last looked at, on the calls'
  // glyph and, the panel folded, on the logo; the page looked at clears it (iOS clearMissedCallsBadge)
  const [missed, setMissed] = useState(0);
  const lookMissed = () => (pane === "calls" ? invoke("calls_seen").then(() => 0) : invoke("calls_missed")).then(setMissed).catch(() => {});
  useEffect(() => {
    invoke("core_info").then(setCore).catch((e) => setFailed(String(e)));
    look();
  }, []);
  useEffect(() => { lookMissed(); }, [pane]);
  useChanged(() => { look(); onPerson(); lookMissed(); });
  // the list learns the unsent words of a chat when it is left (iOS showDraft at openConv's change)
  useEffect(() => {
    window.addEventListener("montana-drafts", look);
    return () => window.removeEventListener("montana-drafts", look);
  }, []);
  useEffect(() => { invoke("chat_focus", { chat: open }); }, [open]);   // no banner for the chat before the eyes
  useEffect(() => {
    const id = setTimeout(() => (query.trim().length >= 2 ? invoke("search", { q: query }).then(setFound) : setFound([])), 200);
    return () => clearTimeout(id);
  }, [query]);
  const coreBad = failed || (core && (core.error != null || core.live < core.min_live));
  // THE UNREAD ARE CHATS, NOT LETTERS (iOS unreadCounts.count): every chat with a letter of theirs unread, or marked by hand
  const unread = (rows || []).filter((r) => r.unread > 0 || r.marked).length;
  const q = query.trim().toLowerCase();
  const archived = (rows || []).filter((r) => r.archived);
  // the archive's own list; a search over every chat out of it; else the chosen folder's chats
  const shown = (rows || []).filter((r) => (archive ? r.archived : q ? !r.archived : takes(tab, r)))
    .filter((r) => !q || chatName(r.name).toLowerCase().includes(q) || r.last.toLowerCase().includes(q));
  const go = (p) => {
    setDrawer(false);
    if (p === "drawer") {
      invoke("seats_state").then((s) => setParked(s.parked)).catch(() => {});
      return setDrawer(true);
    }
    // the panel's first slot while something stands in the way (iOS slot 0): the banners' page, the copy with contacts
    if (p === "notifications") return setOver({ settings: "notifications" });
    // THE TIME COIN IS A PAGE OVER THE APP (iOS ui.walletPage), never a page under the panel
    if (p === "wallet") return setOver("wallet");
    if (p === "keeping") return setOver({ settings: "data" });
    if (p === "chats") setArchive(false);   // the chats' slot always leads to the chats, out of the archive
    if (p === "music" || p === "gallery") {
      setMedia(p);
      try { localStorage.setItem("lastMediaPane", p); } catch { /* kept only where storage is */ }
    }
    setPane(p);
  };
  const write = (r) => { setOver(null); setPeople([]); setPane("chats"); setOpen(r); };
  // A PAGE'S LETTER IN ITS CHAT (iOS ui.showLetter, ui.pendingForwardMany): the page closes, the chat opens at the letter -- asked again,
  // it goes again -- or with its forward picker over the letters chosen
  const showLetter = (r, mid) => { write(r); setFocus(null); setTimeout(() => setFocus(mid), 0); };
  const forwardFrom = (r, mids) => { write(r); setForward({ chat: r, mids }); };
  // THE BAR'S WAYS OUT (iOS MontanaPlayerBar onPlace, onGoTo): a track to its row on the music page, a voice to its letter
  const now = player.usePlayer();
  // THE ROOM THE ROWS KEEP IS THE BAR'S MEASURED HEIGHT (iOS playerReserve, mtPageAction(reserve:)): the mini's or the unfolded plate's
  const reserve = useRef(null);
  useEffect(() => {
    const el = reserve.current;
    if (!el || typeof ResizeObserver === "undefined") return undefined;
    const ro = new ResizeObserver(() => list.current?.style.setProperty("--player", `${el.offsetHeight}px`));
    ro.observe(el);
    return () => ro.disconnect();
  }, [open, pane]);
  useEffect(() => {
    const toPlace = (e) => { setOver(null); setPeople([]); go("music"); player.askPlace(e.detail); };
    const toLetter = (e) => showLetter(e.detail.chat, e.detail.mid);
    // the big player's search is the music page's own, with the keys (iOS onSearch)
    const toSearch = () => { setOver(null); setPeople([]); go("music"); setTimeout(() => list.current?.querySelector("input")?.focus(), 80); };
    window.addEventListener("montana-music-show", toPlace);
    window.addEventListener("montana-show-letter", toLetter);
    window.addEventListener("montana-music-search", toSearch);
    // THE WALLET'S ONE ROAD (iOS montanaOpenWallet): a chat's wallet mark lays the wallet's page over the app
    const toWallet = () => go("wallet");
    window.addEventListener("montana-wallet", toWallet);
    return () => {
      window.removeEventListener("montana-wallet", toWallet);
      window.removeEventListener("montana-music-show", toPlace); window.removeEventListener("montana-show-letter", toLetter);
      window.removeEventListener("montana-music-search", toSearch);
    };
  });
  // A MOVE BETWEEN SEATS (iOS MTSeats.move): refused while a call stands -- the drawer then simply stays as it was
  const seat = (id) => {
    setDrawer(false); setMoving(true);
    invoke("seat_switch", { id }).catch(() => setMoving(false));
  };
  const addPerson = () => {
    let carry = null;
    try { carry = localStorage.getItem("chatWall.page"); } catch { /* the ground stays where it was */ }
    setDrawer(false); setMoving(true);
    invoke("seat_add", { carry }).catch(() => setMoving(false));
  };
  if (moving) return <div className="splash"><span className="spinner" /></div>;

  // A PAGE OVER THE APP COVERS IT WHOLE (iOS: what a pushed page or a sheet covers is not read nor touched): the screen under it
  // leaves the keyboard's way and the reader's tree until the page leaves
  const covered = !!(over || qrFull || newGroup || newChannel || people.length);
  // THE ROWS RUN ON UNDER THE BAR (iOS MTChatListFrame.runsToEdges, the author's word 23.09: «the feed to the end of the screen,
  // as in the chats»): the list's head -- the time panel, the search, the folders -- is measured, and every pane's rows start at
  // its foot as they always did but scroll on beneath it, sinking into the ground by the chat's own wash (CSS .list > .rows)
  const list = useRef(null);
  const chatRows = pane === "chats" && !!rows && rows.length > 0;
  // FOLDED WITH THE BAR (iOS listHead): the search folds with the panel's glyphs; what stays is the search's own hairline, and a tap
  // on it unfolds both; a search typed keeps its field
  const panelOpen = usePanelOpen();
  const searchBox = panelOpen || query ? (
    <div className="search">
      <input type="search" placeholder={t("Search")} value={query} onChange={(e) => setQuery(e.target.value)} />
    </div>
  ) : (
    <button className="row-hairline" aria-label={t("Search")} onClick={() => turnPanel(true, "hairline")} />
  );
  // THE COIN IN THE PULL TURNS THE PANEL (iOS MontanaCoinSpinner, onSettled: turnPanel(open: !barOpen, by: "coin")): any list drawn down
  // at its top -- the wheel or the touchpad here -- brings the coin, which turns with the pull; let go past 140 it folds the panel, or
  // unfolds it, the page staying. The list a page scrolls is the one under the pointer.
  const [pull, setPull] = useState(0);
  const [released, setReleased] = useState(null);
  const pullRef = useRef({ p: 0, idle: 0 });
  useEffect(() => () => clearTimeout(pullRef.current.idle), []);
  const pullWheel = (e) => {
    const r = pullRef.current;
    if (e.deltaY >= 0 && r.p === 0) return;
    for (let el = e.target; el && el !== list.current; el = el.parentElement) {
      if (el.scrollHeight > el.clientHeight + 1 && /(auto|scroll)/.test(getComputedStyle(el).overflowY) && el.scrollTop > 0) return;
    }
    r.p = Math.max(0, Math.min(PULL.full, r.p - e.deltaY * (e.deltaMode === 1 ? 33 : 1) * 0.5));
    setPull(r.p);
    clearTimeout(r.idle);
    r.idle = setTimeout(() => {
      const armed = r.p >= PULL.trigger;
      r.p = 0;
      setPull(0);
      if (!armed) return;
      setReleased({ at: performance.now(), angle: pullAngle(PULL.trigger) });
      turnPanel(!panelOpen, "coin");
      setTimeout(() => setReleased(null), PULL.finish + 150);
    }, 220);
  };
  useEffect(() => {
    const el = list.current;
    if (!el || typeof ResizeObserver === "undefined") return undefined;
    const measure = () => {
      let head = 0;
      for (const c of el.children) {
        if (c.classList.contains("rows") || c.classList.contains("feed-pane")) break;
        head = Math.max(head, c.offsetTop + c.offsetHeight);
      }
      el.style.setProperty("--head", `${head}px`);
    };
    const watch = new ResizeObserver(measure);
    watch.observe(el);
    for (const c of el.children) watch.observe(c);
    measure();
    return () => watch.disconnect();
  }, [pane, !!(rows && rows.length), archive, q]);
  // THE ARROW BACK TO THE TOP (iOS MTToTopButton): a glass circle of 44 with «arrow.up» in the pages' corner, over the corner's own
  // button; it stands while the list's first screen is out of sight and leaves at the top, in a short fade with a small scale
  const [toTop, setToTop] = useState(null);   // the list it would take back
  useEffect(() => {
    const el = list.current;
    if (!el) return undefined;
    const seen = (e) => {
      const s = e.target;
      if (!(s instanceof HTMLElement) || s.parentElement !== el || !(s.classList.contains("rows") || s.classList.contains("feed-pane"))) return;
      const head = parseFloat(getComputedStyle(el).getPropertyValue("--head")) || 0;
      setToTop(s.scrollTop > s.clientHeight - head ? s : null);
    };
    el.addEventListener("scroll", seen, true);
    return () => el.removeEventListener("scroll", seen, true);
  }, []);
  useEffect(() => { setToTop(null); }, [pane]);
  // THE LEFT EDGE OPENS THE DRAWER (iOS MontanaDrawerController's screen-edge pan): a press within the window's first 16 points carried
  // 40 to the right opens it, the mouse's or the finger's alike
  const edge = useRef(null);
  useLeave(() => setDrawer(false), drawer);   // the drawer leaves by Esc as by a tap on its dim
  const edgeDown = (e) => { edge.current = !drawer && e.clientX <= 16 ? { x: e.clientX, y: e.clientY } : null; };
  const edgeMove = (e) => {
    const s = edge.current;
    if (!s || !(e.buttons & 1)) return;
    if (Math.abs(e.clientY - s.y) > 40) { edge.current = null; return; }
    if (e.clientX - s.x > 40) { edge.current = null; go("drawer"); }
  };
  return (
    <div className={"shell" + (drawer ? " drawer-open" : "")} onPointerDown={edgeDown} onPointerMove={edgeMove} onPointerUp={() => (edge.current = null)}>
      <Drawer open={drawer} person={person} unread={unread} version={VERSION} onClose={() => setDrawer(false)}
              parked={parked} onSeat={seat} onAdd={addPerson}
              onApp={go} onMe={() => { setDrawer(false); setOver("me"); }} onSettings={() => { setDrawer(false); setOver("settings"); }} />
      <div className="split" data-pane={pane} data-open={open && pane === "chats" ? "1" : "0"} data-person={person.name}
           data-core={core ? `abi ${core.abi} live ${core.live}/${core.sources.length}` : "pending"} inert={covered || undefined}>
        <PageGround />
        <aside className={"list" + (now.file && !(open && pane === "chats") ? " playing" : "")} ref={list} onWheel={pullWheel}>
          {(pull > PULL.start || released) && <div className="list-spin"><CoinSpinner pull={pull} released={released} /></div>}
          <TopBar pane={pane} unread={unread} missed={missed} mediaIsMusic={media === "music"} onPane={go} />
          {!chatRows && pane !== "feed" && pane !== "contacts" && searchBox}
          {chatRows && !archive && <FolderTabs folders={folders} rows={rows} chosen={tab.id} onPick={pick} onOpen={(opening) => setOver({ folders: opening })} />}
          {chatRows && (
            <div className="rows">
              {/* the search is the chats list's first row and scrolls with it (iOS: «the list's first row is the search») */}
              {searchBox}
              {archive && (
                <button className="archive-back" onClick={() => setArchive(false)}><Glyph name="back" size={16} color="var(--blue)" />{t("Chats")}</button>
              )}
              {!archive && !q && <KeepAsk />}
              {!archive && archived.length > 0 && !q && tab.id === ALL && <ArchiveRow count={archived.length} onOpen={() => setArchive(true)} />}
              {shown.map((r) => <ChatRow key={r.ref} row={r} active={r.ref === open} onOpen={() => setOpen(r.ref)} me={person}
                                          onMenu={(e) => setRowMenu({ row: r, x: e.clientX, y: e.clientY })} />)}
              {/* no chat but Saved Messages: the code's card under it (iOS: «No chats yet» under Saved Messages) */}
              {pane === "chats" && !archive && !q && rows && rows.every((r) => r.ref === SAVED) && <QRCard person={person} onScan={() => setMeeting(true)} />}
              {shown.length === 0 && q && found.length === 0 && <div className="no-results">{t("No results")}</div>}
              {shown.length === 0 && !q && !archive && tab.id !== ALL && <FolderEmpty />}
              {q && found.length > 0 && <div className="found-head">{t("Messages")}</div>}
              {q && found.map((f) => (
                <div key={f.chat + f.mid} className="row found" role="button" tabIndex={0} onClick={() => { setOpen(f.chat); setFocus(f.mid); }}>
                  <Face chat={f.chat} version={f.face} size={48} />
                  <div className="words">
                    <div className="top"><span className="name">{chatName(f.name)}</span><span className="time">{rowTime(f.at)}</span></div>
                    <div className="bottom"><span className="preview">{f.text}</span></div>
                  </div>
                </div>
              ))}
            </div>
          )}
          {pane === "chats" && rows && rows.length > 0 && (
            <button className="compose-door" onClick={() => setComposeMenu(true)} aria-label={t("Write")}>
              <Glyph name="compose" size={22} color="var(--ink)" />
            </button>
          )}
          {pane === "contacts" && <Contacts query={query} head={searchBox} onWrite={write} onProfile={(r) => setOver({ peer: r })} />}
          {pane === "contacts" && (
            // THE CONTACTS' SHARE, bottom right (iOS ContactsTabView mtPageAction + MontanaCardShare): the chats' compose door one
            // to one with the share glyph on it -- my card's link of the kind the code page chose, in the system's share sheet;
            // the link is copied when the sheet will not open
            <button className="compose-door" aria-label={t("Share")} onClick={async () => {
              const c = await invoke("card", {}).catch(() => null);
              const shown = c ? await invoke("share_text", { title: "Montana", text: c.link, link: c.link }).catch(() => false) : false;
              if (c && !shown) invoke("card_copy").catch(() => {});
            }}>
              <Glyph name="share" size={22} color="var(--ink)" />
            </button>
          )}
          {pane === "calls" && <Calls onNewCall={() => go("contacts")} onBlock={(r) => setBlocking({ ref: r.chat, name: r.name })} />}
          {pane === "chess" && <ChessPane query={query} />}
          {pane === "gallery" && <Gallery query={query} onOpen={write} />}
          {pane === "music" && <Music query={query} />}
          {pane === "card" && <CardPane />}
          {pane === "passwords" && <PasswordsPane />}
          {pane === "feed" && <FeedPane query={query} head={searchBox} />}
          {pane === "vpn" && <VpnPane query={query} />}
          {pane === "p2p" && <P2pPane />}
          {NOT_YET[pane] && <NotYet title={NOT_YET[pane]} />}
          {/* THE ONE FLOATING PLAYER OF THE PAGES (iOS MontanaChatsList.playerBar): over the rows' bottom, the rows keeping its room;
              while a chat stands beside the list the bar is the chat's, over its feed */}
          {!(open && pane === "chats") && <div className="player-float" ref={reserve}><PlayerBar /></div>}
          <button className={"to-top" + (toTop ? " on" : "")} aria-label={t("Back to top")} inert={!toTop || undefined}
                  onClick={() => toTop?.scrollTo({ top: 0, behavior: "smooth" })}>
            <Glyph name="arrowUp" size={17} color="#fff" />
          </button>
          {coreBad && (
            <footer className="core-failed">
              {t("The core did not answer")}: {failed ?? core.error ?? `${core.live}/${core.min_live}`}
            </footer>
          )}
        </aside>
        <main className="chat">
          {open && pane === "chats" && <Conversation chat={open} narrow={narrow} myName={person.name} myFace={person.face} focus={focus}
                                                       forward={forward?.chat === open ? forward.mids : null} onForwardTaken={() => setForward(null)}
                                                       onOpenChat={(r) => { setFocus(null); setOpen(r); }} onBack={() => setOpen(null)} />}
        </main>
        {rowMenu && <RowMenu at={rowMenu} onClose={() => setRowMenu(null)} onDelete={() => { setErasing(rowMenu.row); setRowMenu(null); }}
                             onBlock={(r) => setBlocking(r)} />}
        {blocking && <BlockSheet name={blocking.name} onClose={() => setBlocking(null)}
                                 onBlock={() => { invoke("chat_block", { chat: blocking.ref, on: true }); setBlocking(null); }} />}
        {erasing && <EraseSheet row={erasing} onClose={() => setErasing(null)}
                                onErased={(r) => { setErasing(null); if (open === r) setOpen(null); setTimeout(look, 300); }} />}
        {meeting && <MeetSheet onClose={() => setMeeting(false)} onOpened={(r) => { setMeeting(false); setPane("chats"); setOpen(r); look(); }} />}
        {drawer && <div className="drawer-dim" onClick={() => setDrawer(false)} />}
        {composeMenu && (
          <div className="menu-shade" onClick={() => setComposeMenu(false)}>
            <div className="letter-menu compose-menu" onClick={(e) => e.stopPropagation()} role="menu">
              <div className="menu-rows">
                <button className="menu-row" role="menuitem" onClick={() => { setComposeMenu(false); setQrFull(true); }}><span>{t("My code and link")}</span><Glyph name="link" size={18} /></button>
                <button className="menu-row" role="menuitem" onClick={() => { setComposeMenu(false); setMeeting(true); }}><span>{t("Scan code")}</span><Glyph name="qrScan" size={18} /></button>
                <button className="menu-row" role="menuitem" onClick={() => { setComposeMenu(false); setNewGroup(true); }}><span>{t("New Group")}</span><Glyph name="contacts" size={18} /></button>
                <button className="menu-row" role="menuitem" onClick={() => { setComposeMenu(false); setNewChannel(true); }}><span>{t("New Channel")}</span><Glyph name="antenna" size={18} /></button>
              </div>
            </div>
          </div>
        )}
      </div>
      <CallLayer person={person} />
      <RoomLayer />
      {qrFull && (
        <Page title={t("My code and link")} onClose={() => setQrFull(false)}>
          <QRCard person={person} onScan={() => { setQrFull(false); setMeeting(true); }} />
        </Page>
      )}
      {newGroup && <GroupCreate onClose={() => setNewGroup(false)} onMade={(r) => { setNewGroup(false); setPane("chats"); setOpen(r); look(); }} />}
      {newChannel && <ChannelCreate onClose={() => setNewChannel(false)} onMade={(r) => { setNewChannel(false); setPane("chats"); setOpen(r); look(); }} />}
      {/* a page leaves after its way out: it closes itself only, never the page opened over the app meanwhile */}
      {(over === "settings" || over?.settings) && <Settings start={over?.settings} onClose={() => { const was = over; setOver((o) => (o === was ? null : o)); }} onGone={() => window.location.reload()} />}
      {over === "wallet" && <WalletPage person={person} onOpenChat={write} onClose={() => setOver((o) => (o === "wallet" ? null : o))} />}
      {over?.folders && <FoldersPage opening={over.folders} onClose={() => { const was = over; setOver((o) => (o === was ? null : o)); }} />}
      {over === "me" && <MyPage person={person} onClose={() => setOver((o) => (o === "me" ? null : o))} onChanged={onPerson} />}
      {over?.peer && <PeerPage chat={over.peer.ref} face={over.peer.face} myName={person.name} onClose={() => { const was = over; setOver((o) => (o === was ? null : o)); }} onWrite={() => write(over.peer.ref)}
                               onShowLetter={(mid) => showLetter(over.peer.ref, mid)} onForward={(mids) => forwardFrom(over.peer.ref, mids)} />}
      {people.map((pg) => {
        // the page leaves after its way out (Page): it takes itself off, never a page opened meanwhile over the app
        const back = () => setPeople((s) => s.filter((x) => x !== pg));
        if (pg.post) return <PostPage key={pg.key} wall={pg.post.wall} id={pg.post.id} focus={pg.post.comment} onClose={back} />;
        return pg.me
          ? <MyPage key={pg.key} person={person} onClose={back} onChanged={onPerson} />
          : <PeerPage key={pg.key} chat={pg.ref} myName={person.name} onClose={back} onWrite={() => write(pg.ref)}
                      onShowLetter={(mid) => showLetter(pg.ref, mid)} onForward={(mids) => forwardFrom(pg.ref, mids)} />;
      })}
    </div>
  );
}
