import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import TopBar, { Glyph, turnPanel, usePanelOpen } from "./TopBar.jsx";
import { CoinSpinner, PULL, pullAngle } from "./Coin.jsx";
import { ArchiveRow, BOT, BOT_LINK, BOT_ROW, ChatRow, EraseSheet, Face, MeetSheet, PersonMenu, QRCard, RowMenu, SAVED, SelfFace, Swipe, hourOf, rowTitle, seenText, useChanged } from "./Chats.jsx";
import { ALL, FolderEmpty, FoldersPage, FolderTabs, takes, useFolders } from "./Folders.jsx";
import { useLibrary } from "./Library.jsx";
import { useLeave } from "./leave.js";
import { useStrokes } from "./turn.js";
import { Calls, Contacts, Drawer, Gallery, Music, NotYet } from "./Panes.jsx";
import { ChessPane } from "./Chess.jsx";
import Settings, { DataStorage, KeepAsk, NotificationsPage, Page, VERSION } from "./Settings.jsx";
import CardPane from "./Card.jsx";
import { PageGround } from "./Ground.jsx";
import { FeedPane, PostPage } from "./Wall.jsx";
import { WalletPage } from "./Wallet.jsx";
import VpnPane, { P2pPane } from "./Vpn.jsx";
import PasswordsPane from "./Passwords.jsx";
import { MyPage, PeerPage } from "./Profile.jsx";
import { BlockSheet } from "./Safety.jsx";
import { ChannelCreate, GroupCreate, GroupFace } from "./Groups.jsx";
import CallLayer, { callTo } from "./Call.jsx";
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

/** THE LIST'S HEAD, MEASURED (iOS MTChatListFrame): the time panel, the search and the folders above a page's rows; the rows start at
 *  its foot and scroll on beneath it (CSS .list > .rows). */
function useHead(ref, deps) {
  useEffect(() => {
    const el = ref.current;
    if (!el || typeof ResizeObserver === "undefined") return undefined;
    const measure = () => {
      let head = 0;
      for (const c of el.children) {
        if (c.classList.contains("rows") || c.classList.contains("feed-pane")) break;
        if (c.classList.contains("ghost")) continue;
        head = Math.max(head, c.offsetTop + c.offsetHeight);
      }
      el.style.setProperty("--head", `${head}px`);
    };
    const watch = new ResizeObserver(measure);
    watch.observe(el);
    for (const c of el.children) watch.observe(c);
    measure();
    return () => watch.disconnect();
  }, deps);
}

const NOT_YET = { mesh: "Mesh wall" };
/** The pages that search their own rows (iOS ChatsListView.searchesItself). */
const SEARCHES_ITSELF = new Set(["music", "feed", "vpn", "mesh", "p2p", "gallery"]);
/** The globe's page at the row's end (iOS UIState.globeWall), as the panel's globe opens it. */
const GLOBE = "vpn";

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
  const [rowMenu, setRowMenu] = useState(null);   // the archive's menu at the pointer: {row, x, y}
  const [personMenu, setPersonMenu] = useState(null);   // the menu about a person at its row: {row, top, left}
  const [selecting, setSelecting] = useState(false);    // the selection (iOS ChatsListView.selecting), entered by the menu's «Select»
  const [chosen, setChosen] = useState(() => new Set());
  const [swiped, setSwiped] = useState(null);           // the one row standing open on its tiles: {ref, side}
  const [erasing, setErasing] = useState(null);
  const [drawer, setDrawer] = useState(false);
  const [drawerMoving, setDrawerMoving] = useState(false);   // the drawer on its way: the page sliding under the finger or the spring
  const [ghost, setGhost] = useState(null);        // the page sliding in beside the pane under the finger: {pane, side}
  const [searchFocused, setSearchFocused] = useState(false);
  const [parked, setParked] = useState([]);        // the persons of this computer waiting on the shelf (iOS MTSeats)
  const [moving, setMoving] = useState(false);     // a move between seats: the program starts again in the other folder
  const [over, setOver] = useState(null);          // the page over the app: "settings", "me", {peer}
  const [archive, setArchive] = useState(false);    // the archive's own list
  // THE ARCHIVE'S ROW IS SUMMONED (iOS archiveRevealed): a pull down past 25 at the list's top brings it, a stroke up folds it
  const [archiveShown, setArchiveShown] = useState(false);
  const [blocking, setBlocking] = useState(null);   // the row whose block is asked
  // THE SEARCH'S HITS OF THE WORD THAT SETTLED (iOS SearchHits): the chats, groups and contacts by name, and the letters
  const [hits, setHits] = useState({ q: "", chats: [], found: [] });
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
  const endSelecting = () => { setSelecting(false); setChosen(new Set()); };
  const pick = (id) => { endSelecting(); setFolder(id); setPane("chats"); };
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
  // the three reads one word of the book asks for, answered together before the next word asks again (Chats.jsx useChanged)
  useChanged(() => Promise.allSettled([look(), onPerson(), lookMissed()]));
  // the list learns the unsent words of a chat when it is left (iOS showDraft at openConv's change)
  useEffect(() => {
    window.addEventListener("montana-drafts", look);
    return () => window.removeEventListener("montana-drafts", look);
  }, []);
  useEffect(() => { invoke("chat_focus", { chat: open }); }, [open]);   // no banner for the chat before the eyes
  // THE SEARCH IS A COMPUTATION ONCE THE KEYS SETTLE (iOS refreshSearchHits: 120 ms): the list's rows -- not the archived -- whose
  // shown name or key holds the word, and the letters the core finds (the newest sixty), told together
  useEffect(() => {
    const word = query.toLowerCase();
    if (!word) { setHits({ q: "", chats: [], found: [] }); return undefined; }
    let live = true;
    const id = setTimeout(() => {
      const chats = (rows || []).filter((r) => !r.archived && `${rowTitle(r.ref, r.name)} ${r.ref}`.toLowerCase().includes(word));
      invoke("search", { q: query }).catch(() => []).then((found) => { if (live) setHits({ q: word, chats, found: found || [] }); });
    }, 120);
    return () => { live = false; clearTimeout(id); };
  }, [query, rows]);
  // THE SEARCH IS ACTIVE while its field holds the keys or a word (iOS searchActive)
  const searchActive = searchFocused || query !== "";
  // THE PRESENCE UNDER A PERSON'S NAME IN THE RESULTS (iOS contactRow: store.presenceWord): asked for the persons the results show
  const [seen, setSeen] = useState({});
  const [seenExact, setSeenExact] = useState(true);
  useEffect(() => { invoke("settings_get").then((x) => setSeenExact(x.presenceSharing !== false)).catch(() => {}); }, []);
  const recent = (rows || []).filter((r) => !r.archived && !r.group && r.ref !== SAVED).slice(0, 12);   // iOS recentContacts
  const seenKey = searchActive ? (query ? hits.chats : recent).filter((r) => !r.group && r.ref !== SAVED).map((r) => r.ref).join(",") : "";
  useEffect(() => {
    if (!seenKey) return undefined;
    let live = true;
    Promise.all(seenKey.split(",").map((c) => invoke("presence", { chat: c }).then((x) => [c, x]).catch(() => [c, null])))
      .then((l) => { if (live) setSeen(Object.fromEntries(l)); });
    return () => { live = false; };
  }, [seenKey]);
  const coreBad = failed || (core && (core.error != null || core.live < core.min_live));
  // THE UNREAD ARE CHATS, NOT LETTERS (iOS unreadCounts.count): every chat with a letter of theirs unread -- the hand's mark is the
  // row's dot, never a count; the drawer's Chats counts the chats alone, not the groups and the channels (MTApplication.badge)
  const unread = (rows || []).filter((r) => r.unread > 0).length;
  const unreadChats = (rows || []).filter((r) => r.unread > 0 && !r.group).length;
  const q = query.trim().toLowerCase();
  const archived = (rows || []).filter((r) => r.archived);
  // the archive's own list, else the chosen folder's chats (a search lays its results over them)
  const shown = (rows || []).filter((r) => (archive ? r.archived : takes(tab, r)))
    // OUR BOT after the conversations (iOS live = orderedChats + [MTBot.chat]): in All and in a folder that takes bots
    .concat(!archive && rows && takes(tab, BOT_ROW) ? [BOT_ROW] : []);
  const go = (p) => {
    setDrawer(false);
    if (p === "drawer") {
      invoke("seats_state").then((s) => setParked(s.parked)).catch(() => {});
      return setDrawer(true);
    }
    // THE PANEL'S FIRST SLOT WHILE SOMETHING STANDS IN THE WAY (iOS slot 0, MontanaChatsList.swift 373, 493): the banners' page or Data
    // and Storage alone, each a page of its own over the app with its cross -- never the Settings under it (iOS overlayPage
    // .notifications, .keeping, ContentView.swift 2467-2478)
    if (p === "notifications") return setOver("notifications");
    // THE TIME COIN IS A PAGE OVER THE APP (iOS ui.walletPage), never a page under the panel
    if (p === "wallet") return setOver("wallet");
    if (p === "keeping") return setOver("keeping");
    if (p === "chats") setArchive(false);   // the chats' slot always leads to the chats, out of the archive
    if (p === "music" || p === "gallery") {
      setMedia(p);
      try { localStorage.setItem("lastMediaPane", p); } catch { /* kept only where storage is */ }
    }
    // A PAGE THAT SEARCHES ITSELF KEEPS ITS WORD TO ITSELF (iOS ChatsListView.onChange(of: ui.pane)): the word typed over the tracks,
    // the feed or a wall does not follow the person to another page, nor a word typed elsewhere to them
    if (p !== pane && (SEARCHES_ITSELF.has(p) || SEARCHES_ITSELF.has(pane)) && (query || searchFocused)) {
      setQuery("");
      setSearchFocused(false);
      if (list.current?.contains(document.activeElement)) document.activeElement.blur();
    }
    setPane(p);
  };
  // THE ROW OF PAGES UNDER THE BAR, in the panel's order (iOS UIState.turnOrder): the contacts, the calls, the feed, the chats, the
  // dynamic glyph's page -- the music while the glyph is the music's, else the gallery -- and the globe's wall
  const mediaIsMusic = pane === "music" || (pane !== "gallery" && media !== "gallery");
  const turnOrder = ["contacts", "calls", "feed", "chats", mediaIsMusic ? "music" : "gallery", GLOBE];
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
  // A PAGE OVER THE APP COVERS IT WHOLE (iOS: what a pushed page or a sheet covers is not read nor touched): the screen under it
  // leaves the keyboard's way and the reader's tree until the page leaves
  const covered = !!(over || qrFull || newGroup || newChannel || people.length);
  // THE COVER NEVER OUTLIVES ITS PAGE (the freeze of the panel's first slot, 25.10.2026): the app is out of reach only while a page
  // stands over it to take the touch; covered with no live page over it for more than a second, the window would take none at all --
  // the trace is told, and the cover is taken away, whatever left it so
  const cover = useRef(null);
  cover.current = { over, people: people.length, qrFull, newGroup, newChannel, moving };
  useEffect(() => {
    if (!covered) return undefined;
    let since = 0;
    const id = setInterval(() => {
      const live = document.visibilityState !== "visible" || cover.current.moving
        || [...document.querySelectorAll('[role="dialog"]')].some((d) => !d.closest('[inert], [aria-hidden="true"]'));
      if (live) { since = 0; return; }
      if (!since) { since = performance.now(); return; }
      if (performance.now() - since < 1000) return;
      clearInterval(id);
      const c = cover.current;
      const what = typeof c.over === "string" ? c.over : c.over ? Object.keys(c.over)[0] : "none";
      invoke("trace", { line: `cover freed: no page stood over the app for 1 s over=${what} people=${c.people} qr=${c.qrFull ? 1 : 0} group=${c.newGroup ? 1 : 0} channel=${c.newChannel ? 1 : 0}` }).catch(() => {});
      setOver(null); setPeople([]); setQrFull(false); setNewGroup(false); setNewChannel(false);
    }, 250);
    return () => clearInterval(id);
  }, [covered]);
  // THE ROWS RUN ON UNDER THE BAR (iOS MTChatListFrame.runsToEdges, the author's word 23.09: «the feed to the end of the screen,
  // as in the chats»): the list's head -- the time panel, the search, the folders -- is measured, and every pane's rows start at
  // its foot as they always did but scroll on beneath it, sinking into the ground by the chat's own wash (CSS .list > .rows)
  const list = useRef(null);
  const chatRows = pane === "chats" && !!rows && rows.length > 0;
  // FOLDED WITH THE BAR (iOS listHead): the search folds with the panel's glyphs; what stays is the search's own hairline, and a tap
  // on it unfolds both; a search typed keeps its field
  const panelOpen = usePanelOpen();
  // THE PLATFORM'S SEARCH BAR (iOS MTSearchField, searchBar): its field -- the magnifier, «Search», the clear key while a word stands --
  // and, while the search is active, the cross on the glass (44, xmark 15): it takes the word away and the keys with it. The bar's
  // microphone is the system's dictation, which a page of Windows cannot start: Windows' own is Win+H, into any field.
  const field = useRef(null);
  const searchBox = panelOpen || query || searchFocused ? (
    <div className="search">
      <div className="search-field">
        <svg className="search-glass" width="15" height="15" viewBox="0 0 24 24" aria-hidden="true">
          <circle cx="10.5" cy="10.5" r="7" fill="none" stroke="currentColor" strokeWidth="2.6" /><path d="M15.8 15.8L21 21" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" />
        </svg>
        <input ref={field} type="search" placeholder={t("Search")} aria-label={t("Search")} value={query} onChange={(e) => setQuery(e.target.value)}
               onFocus={() => setSearchFocused(true)} onBlur={() => setSearchFocused(false)} />
        {query && (
          <button className="search-clear" aria-label={t("Clear text")} onMouseDown={(e) => e.preventDefault()} onClick={() => setQuery("")}>
            <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="currentColor" /><path d="M8.2 8.2l7.6 7.6M15.8 8.2l-7.6 7.6" stroke="#1c1c1e" strokeWidth="2.2" strokeLinecap="round" /></svg>
          </button>
        )}
      </div>
      {searchActive && (
        <button className="search-cancel" aria-label={t("Cancel")} onMouseDown={(e) => e.preventDefault()}
                onClick={() => { setQuery(""); setSearchFocused(false); field.current?.blur(); }}>
          <Glyph name="close" size={15} color="var(--bar-glyph)" />
        </button>
      )}
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
    if (r.p > 25) summonArchive();
    clearTimeout(r.idle);
    r.idle = setTimeout(() => {
      const armed = r.p >= PULL.trigger;
      r.p = 0;
      setPull(0);
      if (!armed) return;
      setReleased({ at: performance.now(), angle: pullAngle(PULL.trigger) });
      invoke("pull_refresh").catch(() => {});   // the refresh (iOS onRefresh: pullRefresh -- the box asked at once)
      turnPanel(!panelOpen, "coin");
      setTimeout(() => setReleased(null), PULL.finish + 150);
    }, 220);
  };
  useHead(list, [pane, !!(rows && rows.length), archive, q]);
  const ghostList = useRef(null);
  useHead(ghostList, [ghost?.pane, !!(rows && rows.length)]);
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
  useLeave(() => setDrawer(false), drawer);   // the drawer leaves by Esc as by a tap on its dim
  // THE STROKES OF THE PAGES (iOS MontanaDrawerController, MTTabPan, UIState.turnStroke): the window's left edge and the row's first
  // page drag the drawer out, the dimmed page drags it back; the page's centre turns the pages of the row -- on the chats page its
  // folders first -- the neighbour sliding in beside it and the puck riding to its glyph
  const shell = useRef(null);
  const split = useRef(null);
  const sheetUp = !!(rowMenu || personMenu || erasing || meeting || composeMenu || blocking);
  const chatOver = narrow && !!open && pane === "chats";
  const strokes = useStrokes(() => ({
    shell: shell.current, split: split.current, list: list.current, drawerOpen: drawer,
    edgeAllowed: () => !covered && !sheetUp && !chatOver,
    // UIState.tabsMayTurn and the page's holds (pageHolds): nothing over the tabs, no search, no menu, no sheet, the archive not pushed
    turnAllowed: () => !covered && !sheetUp && !chatOver && !searchActive && !archive && !selecting,
    atRowStart: () => turnOrder[0] === pane,
    neighbour: (side) => { const i = turnOrder.indexOf(pane); return i < 0 ? null : turnOrder[i + side] ?? null; },
    folderBeside: (step) => {
      if (pane !== "chats" || !chatRows || archive) return false;
      const i = folders.findIndex((f) => f.id === tab.id);
      return i >= 0 && i + step >= 0 && i + step < folders.length;
    },
    ghost: setGhost,
    turned: (p) => flushSync(() => { go(p); setGhost(null); }),
    folderTurned: (step) => {
      const i = folders.findIndex((f) => f.id === tab.id);
      if (folders[i + step]) pick(folders[i + step].id);
    },
    drawerSet: (on) => (on ? go("drawer") : setDrawer(false)),
    drawerMoving: setDrawerMoving,
  }));
  // a tap, a key or a row of the drawer moves it on the same spring (MontanaDrawerController.setOpen)
  const drawerSeen = useRef(drawer);
  useLayoutEffect(() => {
    if (drawerSeen.current === drawer) return;
    drawerSeen.current = drawer;
    strokes.animateDrawer(drawer);
  }, [drawer]);
  // THE DRAWER LEAVES BEFORE ITS DEED (iOS MontanaSideDrawer.leave): it slides home and the deed follows 0.3 s later, once
  const leaving = useRef(false);
  useEffect(() => { if (drawer) leaving.current = false; }, [drawer]);
  const fromDrawer = (deed) => {
    if (leaving.current) return;
    leaving.current = true;
    setDrawer(false);
    setTimeout(deed, 300);
  };
  // the folder of one kind alone (iOS MTChatFolder.onlyKind): one kind, no chats named -- the groups' or the channels' own corner
  const onlyKind = !archive && tab && tab.kinds.length === 1 && !(tab.chats || []).length && ["groups", "channels"].includes(tab.kinds[0]) ? tab.kinds[0] : null;
  // THE SELECTION'S DEEDS (iOS markReadSelected / archiveSelected / deleteSelected): each chosen chat of the list -- not the room
  // without a wire, which the stored list never holds -- then the selection ends
  const toggleChosen = (ref) => setChosen((o) => { const n = new Set(o); if (n.has(ref)) n.delete(ref); else n.add(ref); return n; });
  const onChosen = (deed) => {
    for (const ref of chosen) if (ref !== SAVED) deed(ref);
    endSelecting();
    setTimeout(look, 300);
  };
  // AN OPEN ROW CLOSES at a touch anywhere else, at another page, folder or list (the platform's swipe actions)
  useEffect(() => {
    if (!swiped) return undefined;
    const away = (e) => { if (e.target.closest?.(".swipe-box")?.dataset.swipe !== swiped.ref) setSwiped(null); };
    window.addEventListener("pointerdown", away, true);
    return () => window.removeEventListener("pointerdown", away, true);
  }, [swiped]);
  useEffect(() => { setSwiped(null); }, [pane, folder, archive]);
  // THE ARCHIVE'S ROW, PULLED (iOS onPull: dy > 25 summons it, dy < -25 folds it; All alone, never while searching): the wheel's pull
  // at the top and a touch drawn down at the top bring it; the list scrolled on past 25 folds it again
  function summonArchive() { if (pane === "chats" && !archive && tab.id === ALL && !searchActive && archived.length > 0) setArchiveShown(true); }
  useEffect(() => { if (archived.length === 0 || tab.id !== ALL) setArchiveShown(false); }, [archived.length, tab.id]);
  useEffect(() => {
    const el = list.current;
    if (!el) return undefined;
    let y0 = null;
    const rowsOf = () => el.querySelector(":scope > .rows");
    const start = (e) => { y0 = (rowsOf()?.scrollTop ?? 1) <= 0 ? e.touches[0].clientY : null; };
    const move = (e) => { if (y0 != null && e.touches[0].clientY - y0 > 25) { y0 = null; summonArchive(); } };
    const scroll = (e) => { if (e.target === rowsOf() && e.target.scrollTop > 25) setArchiveShown(false); };
    el.addEventListener("touchstart", start, { passive: true });
    el.addEventListener("touchmove", move, { passive: true });
    el.addEventListener("scroll", scroll, true);
    return () => { el.removeEventListener("touchstart", start); el.removeEventListener("touchmove", move); el.removeEventListener("scroll", scroll, true); };
  });
  // A HOLD ON A ROW (iOS onHold): the menu about a person at the row; in the archive, the platform's menu; nothing while selecting
  const menuFor = (r, e) => {
    if (selecting || r.ref === BOT) return;   // no hold on the bot's row (iOS holdsRow)
    setSwiped(null);
    if (archive) { setRowMenu({ row: r, x: e.clientX, y: e.clientY }); return; }
    const at = e.currentTarget.getBoundingClientRect();
    setPersonMenu({ row: r, top: at.top, left: list.current?.getBoundingClientRect().left ?? 0 });
  };
  // THE TILES OF A ROW'S SWIPES (iOS swipeLeading / swipeTrailing, MontanaChatsList.swift 792-805; the archive's, MontanaScreens.swift 48-57)
  const swipesOf = (r) => {
    if (r.ref === BOT) return {};   // the bot's row has no tiles (iOS swipeTrailing guard; no address for the calls)
    const unread = r.unread > 0 || r.marked;
    const flag = (f, on) => invoke("chat_flag", { chat: r.ref, flag: f, on });
    if (archive) {
      return {
        capsule: true,
        leading: [
          { icon: unread ? "markRead" : "circle", label: t(unread ? "Mark as read" : "Mark as unread"), color: "#0a84ff", act: () => flag("unread", !unread) },
          { icon: r.pinned ? "pinSlash" : "pin", label: t(r.pinned ? "Unpin" : "Pin"), color: "#ff9f0a", act: () => flag("pin", !r.pinned) },
        ],
        trailing: [
          { icon: "unarchive", label: t("Unarchive"), color: "#8e8e93", act: () => flag("archive", false) },
          ...(r.ref !== SAVED ? [{ icon: "trash", label: t("Delete"), color: "#ff453a", act: () => setErasing(r) }] : []),
          { icon: r.muted ? "bellFill" : "bellSlash", label: t(r.muted ? "Unmute" : "Mute"), color: "#5e5ce6", act: () => flag("mute", !r.muted) },
        ],
      };
    }
    // the calls only to a person with an address: never a group, never the room without a wire
    const person = !r.group && r.ref !== SAVED;
    return {
      leading: person ? [
        { icon: "phone", label: t("Audio call"), act: () => callTo(r.ref, r.name, false) },
        { icon: "video", label: t("Video call"), act: () => callTo(r.ref, r.name, true) },
      ] : [],
      trailing: [
        { icon: unread ? "markRead" : "circle", label: t(unread ? "Mark as read" : "Mark as unread"), act: () => flag("unread", !unread) },
        { icon: r.pinned ? "pinSlash" : "pin", label: t(r.pinned ? "Unpin" : "Pin"), act: () => flag("pin", !r.pinned) },
        { icon: r.muted ? "bellFill" : "bellSlash", label: t(r.muted ? "Unmute" : "Mute"), act: () => flag("mute", !r.muted) },
        { icon: "archive", label: t("Archive"), act: () => flag("archive", true) },
        ...(r.ref !== SAVED ? [{ icon: "trash", label: t("Delete"), act: () => setErasing(r) }] : []),   // the local room has no delete
      ],
    };
  };
  // THE SEARCH'S RESULTS (iOS searchResults, MontanaChatsList.swift 1796-1920): the settings' inset groups on the page's ground, under
  // the field -- with no word «CONTACTS», the last twelve people of the list; with a word «CHATS, GROUPS AND CONTACTS» by the shown
  // name, «MESSAGES», and «Nothing found» once the word settled with nothing; a person's row the face 46 with its presence, the name
  // bold and the presence word, a letter's the face, the name, two lines of its words and its hour
  const resultFace = (ref, face, live) => (ref === SAVED ? <SelfFace name={person.name} version={person.face} size={46} />
    : ref.startsWith("grp:") ? <GroupFace size={46} chat={ref} version={face} /> : <Face chat={ref} version={face} size={46} live={live} />);
  const results = () => {
    const word = query.toLowerCase();
    const settled = hits.q === word;
    const group = (head, items) => items.length > 0 && (
      <div className="sect results-sect"><div className="sect-head">{head}</div><div className="sect-rows">{items}</div></div>
    );
    const personRow = (r) => {
      const w = r.group ? "" : r.ref === SAVED ? t("saved messages") : (!r.blocked && seenText(seen[r.ref], seenExact)?.[0]) || "";
      return (
        <div key={r.ref} className="result-row" role="button" tabIndex={0} aria-label={rowTitle(r.ref, r.name)}
             onClick={() => write(r.ref)} onKeyDown={(e) => e.key === "Enter" && write(r.ref)}>
          {resultFace(r.ref, r.face, !r.group && !r.blocked && !!seenText(seen[r.ref], seenExact)?.[1])}
          <div className="result-words"><span className="result-name">{rowTitle(r.ref, r.name)}</span>{w && <span className="result-sub">{w}</span>}</div>
        </div>
      );
    };
    const letterRow = (f) => (
      <div key={f.chat + f.mid} className="result-row" role="button" tabIndex={0} aria-label={`${rowTitle(f.chat, f.name)}: ${f.text}`}
           onClick={() => { write(f.chat); setFocus(f.mid); }} onKeyDown={(e) => { if (e.key === "Enter") { write(f.chat); setFocus(f.mid); } }}>
        {resultFace(f.chat, f.face, false)}
        <div className="result-words"><span className="result-name">{rowTitle(f.chat, f.name)}</span><span className="result-text">{f.text}</span></div>
        <span className="result-time">{hourOf(f.at)}</span>
      </div>
    );
    if (!word) return <div className="search-results">{group(t("Contacts"), recent.map(personRow))}</div>;
    return (
      <div className="search-results">
        {settled && group(t("CHATS, GROUPS AND CONTACTS"), hits.chats.map(personRow))}
        {settled && group(t("Messages"), hits.found.map(letterRow))}
        {settled && !hits.chats.length && !hits.found.length && <div className="nothing-found">{t("Nothing found")}</div>}
      </div>
    );
  };
  // ONE PAGE UNDER THE BAR (iOS paneView): the pane that stands, and the neighbour sliding in beside it under the finger
  const pageOf = (p) => {
    const paneRows = p === "chats" && !!rows && rows.length > 0;
    return (<>
      {!paneRows && p !== "feed" && p !== "contacts" && searchBox}
      {paneRows && !archive && <FolderTabs folders={folders} rows={rows} chosen={tab.id} onPick={pick} onOpen={(opening) => setOver({ folders: opening })} />}
      {/* THE ARCHIVE IS A PAGE PUSHED OVER THE CHATS (iOS ArchivedChatsView: navigationTitle «Archive», inline): its bar -- the way back
          and the title -- stands where the time panel stood */}
      {paneRows && archive && (
        <div className="page-bar archive-bar">
          <button className="glass-mark" onClick={() => setArchive(false)} aria-label={t("Back")}><Glyph name="back" size={18} color="var(--bar-glyph)" /></button>
          <div className="page-title">{t("Archive")}</div>
          <span />
        </div>
      )}
      {paneRows && (
        <div className={"rows" + (searchActive && !archive ? " searching" : "") + (archive ? " archive-list" : "")}>
          {/* the search is the chats list's first row and scrolls with it (iOS: «the list's first row is the search»); the archive,
              a page of its own on iOS, has none; while searching the list stands still under the field and the results scroll in
              their own frame beneath it (iOS MontanaTimePanel pinTop, MTSearchResultsFrame) */}
          {!archive && searchBox}
          {!archive && searchActive && results()}
          {!(searchActive && !archive) && <>
          {!archive && archived.length > 0 && tab.id === ALL && archiveShown && <ArchiveRow count={archived.length} onOpen={() => setArchive(true)} />}
          {shown.map((r) => (
            <Swipe key={r.ref} tag={r.ref} {...swipesOf(r)} enabled={!selecting} side={swiped?.ref === r.ref ? swiped.side : 0}
                   onSide={(sd) => setSwiped((o) => (sd ? { ref: r.ref, side: sd } : o?.ref === r.ref ? null : o))}>
              <ChatRow row={r} active={r.ref === open} me={person} selecting={selecting} chosen={chosen.has(r.ref)}
                       onOpen={() => {
                         setSwiped(null);
                         // the bot's row opens the bot where it lives, never while selecting (iOS rowTapped)
                         if (r.ref === BOT) { if (!selecting) invoke("open_link", { url: BOT_LINK }); return; }
                         if (selecting) toggleChosen(r.ref); else setOpen(r.ref);
                       }}
                       onMenu={(e) => menuFor(r, e)} />
            </Swipe>
          ))}
          {/* no chat but Saved Messages: the code's card under it (iOS: «No chats yet» under Saved Messages) */}
          {/* THE EMPTY ARCHIVE SAYS SO (iOS ArchivedChatsView overlay): «Archive is empty» in grey at the page's middle */}
          {archive && archived.length === 0 && <div className="archive-empty">{t("Archive is empty")}</div>}
          {p === "chats" && !archive && tab.id === ALL && rows && rows.every((r) => r.ref === SAVED) && <QRCard person={person} onScan={() => setMeeting(true)} onExpand={() => setQrFull(true)} />}
          {shown.length === 0 && !archive && tab.id !== ALL && <FolderEmpty />}
          </>}
        </div>
      )}
      {/* THE SELECTION'S BAR (iOS selectionBar, MontanaChatsList.swift 1471-1493): the cross out on the left, then «Read all»,
          «Archive» and «Delete» in red, each a capsule of the glass sharing the width, at half and silent while nothing is chosen */}
      {paneRows && selecting && (
        <div className="chats-select-bar">
          <button className="calls-bar-button" onClick={endSelecting} aria-label={t("Cancel")}><Glyph name="close" size={18} color="#fff" /></button>
          <button className="select-pill" disabled={!chosen.size} onClick={() => onChosen((ref) => invoke("chat_flag", { chat: ref, flag: "unread", on: false }))}>{t("Read all")}</button>
          <button className="select-pill" disabled={!chosen.size} onClick={() => onChosen((ref) => invoke("chat_flag", { chat: ref, flag: "archive", on: true }))}>{t("Archive")}</button>
          <button className="select-pill red" disabled={!chosen.size} onClick={() => onChosen((ref) => invoke("chat_erase", { chat: ref, both: false }))}>{t("Delete")}</button>
        </div>
      )}
      {/* the pages' corner stands while nothing is selected and nothing searched (iOS mtPageAction(shown: !selecting && !searchActive)) */}
      {p === "chats" && rows && rows.length > 0 && !selecting && !searchActive && !onlyKind && (
        <button className="compose-door" onClick={() => setComposeMenu(true)} aria-label={t("Write")}>
          <Glyph name="compose" size={27} color="var(--bar-glyph)" />
        </button>
      )}
      {/* THE CORNER OF A FOLDER OF ONE KIND (iOS createButton): on the Groups or the Channels folder the plus -- 27 medium on the bar's
          plate -- opens a group's two steps or a channel's three */}
      {p === "chats" && rows && rows.length > 0 && !selecting && !searchActive && onlyKind && (
        <button className="compose-door" onClick={() => (onlyKind === "channels" ? setNewChannel(true) : setNewGroup(true))}
                aria-label={t(onlyKind === "channels" ? "Channel" : "Group")}>
          <Glyph name="plus" size={27} color="var(--bar-glyph)" />
        </button>
      )}
      {p === "calls" && searchActive && <div className="rows searching">{results()}</div>}
      {/* the contacts keep their field where it stands (its keys stay) and lay the same results over their rows */}
      {p === "contacts" && <Contacts query={query} head={searchBox} over={searchActive ? results() : null} onWrite={write} onProfile={(r) => setOver({ peer: r })} />}
      {p === "contacts" && (
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
      {p === "calls" && !searchActive && <Calls onNewCall={() => go("contacts")} onBlock={(r) => setBlocking({ ref: r.chat, name: r.name })} />}
      {p === "chess" && <ChessPane query={query} />}
      {p === "gallery" && <Gallery query={query} onOpen={write} />}
      {p === "music" && <Music query={query} />}
      {p === "card" && <CardPane />}
      {p === "passwords" && <PasswordsPane />}
      {p === "feed" && <FeedPane query={query} head={searchBox} />}
      {p === "vpn" && <VpnPane query={query} />}
      {p === "p2p" && <P2pPane />}
      {NOT_YET[p] && <NotYet title={NOT_YET[p]} />}
    </>);
  };
  // A MOVE BETWEEN SEATS DRAWS ITS SPLASH OVER THE APP, NEVER IN ITS PLACE (the review of 25.10.2026): the app stays drawn under it,
  // every hook of this page called as before -- a page that returned the splash before its last hooks drew fewer of them, React
  // threw (#300) and took the whole window away, and a move refused while a call stands (lib.rs seat_switch, seat_add: «call») came
  // back to nothing: a black window until the tray's Quit. Refused, the splash goes and the app stands as it was.
  return (<>
    <div className={"shell" + (drawer ? " drawer-open" : "")} ref={shell} inert={moving || undefined}>
      <Drawer open={drawer} shown={drawer || drawerMoving} person={person} counts={{ chats: unreadChats, calls: missed }} version={VERSION} onClose={() => setDrawer(false)}
              parked={parked} onSeat={(id) => fromDrawer(() => seat(id))} onAdd={() => fromDrawer(addPerson)}
              onApp={(k) => fromDrawer(() => go(k))} onMe={() => fromDrawer(() => setOver("me"))} onSettings={() => fromDrawer(() => setOver("settings"))} />
      <div className="split" data-pane={pane} data-open={open && pane === "chats" ? "1" : "0"} data-person={person.name}
           data-core={core ? `abi ${core.abi} live ${core.live}/${core.sources.length}` : "pending"} inert={covered || undefined} ref={split}>
        <PageGround />
        <aside className={"list" + (now.file && !(open && pane === "chats") ? " playing" : "")} ref={list} onWheel={pullWheel}>
          {(pull > PULL.start || released) && <div className="list-spin"><CoinSpinner pull={pull} released={released} /></div>}
          {!(pane === "chats" && archive) && <TopBar pane={pane} unread={unread} missed={missed} mediaIsMusic={media === "music"} onPane={go} stroke={ghost} />}
          {pageOf(pane)}
          {ghost && (
            <div className={"list ghost" + (now.file && !(open && pane === "chats") ? " playing" : "")} ref={ghostList} style={{ "--side": ghost.side }}
                 inert aria-hidden="true">
              <div className="time-panel" style={{ visibility: "hidden" }}><div className="bar-plate" /></div>
              {pageOf(ghost.pane)}
            </div>
          )}
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
        {rowMenu && <RowMenu at={rowMenu} onClose={() => setRowMenu(null)} onDelete={() => { setErasing(rowMenu.row); setRowMenu(null); }} />}
        {personMenu && <PersonMenu at={personMenu} me={person} onClose={() => setPersonMenu(null)} onDelete={(r) => setErasing(r)}
                                   onBlock={(r) => setBlocking(r)}
                                   onSelect={(r) => { setSwiped(null); setSelecting(true); setChosen(new Set([r.ref])); }} />}
        {blocking && <BlockSheet name={blocking.name} onClose={() => setBlocking(null)}
                                 onBlock={() => { invoke("chat_block", { chat: blocking.ref, on: true }); setBlocking(null); }} />}
        {erasing && <EraseSheet row={erasing} me={person} onClose={() => setErasing(null)}
                                onErased={(r) => { setErasing(null); if (open === r) setOpen(null); setTimeout(look, 300); }} />}
        {meeting && <MeetSheet onClose={() => setMeeting(false)} onOpened={(r) => { setMeeting(false); setPane("chats"); setOpen(r); look(); }} />}
        {(drawer || drawerMoving) && <div className="drawer-dim" onClick={() => setDrawer(false)} />}
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
      {/* the copy's question at the opening, over the window (iOS keepAsk alert) */}
      <KeepAsk />
      <CallLayer person={person} pillHidden={pane === "chats" && !open} />
      <RoomLayer />
      {qrFull && (
        // THE CODE'S FULL PAGE (iOS MontanaQRFullView): no title, the code's column; «Scan» closes it and the scanner follows 0.4 s later
        <Page title="" onClose={() => setQrFull(false)}>
          <QRCard person={person} titled={false} onScan={() => { setQrFull(false); setTimeout(() => setMeeting(true), 400); }} />
        </Page>
      )}
      {/* the new group or channel opens 0.4 s after its steps leave (iOS creatingGroup / creatingChannel: asyncAfter 0.4) */}
      {newGroup && <GroupCreate onClose={() => setNewGroup(false)} onMade={(r) => { setNewGroup(false); setPane("chats"); look(); setTimeout(() => setOpen(r), 400); }} />}
      {newChannel && <ChannelCreate onClose={() => setNewChannel(false)} onMade={(r) => { setNewChannel(false); setPane("chats"); look(); setTimeout(() => setOpen(r), 400); }} />}
      {/* a page leaves after its way out: it closes itself only, never the page opened over the app meanwhile */}
      {over === "settings" && <Settings key="settings" onClose={() => setOver((o) => (o === "settings" ? null : o))} onGone={() => window.location.reload()} />}
      {over === "keeping" && <DataStorage key="keeping" motion="slot" onClose={() => setOver((o) => (o === "keeping" ? null : o))} />}
      {over === "notifications" && <NotificationsPage key="notifications" motion="slot" onClose={() => setOver((o) => (o === "notifications" ? null : o))} />}
      {over === "wallet" && <WalletPage person={person} onOpenChat={write} onClose={() => setOver((o) => (o === "wallet" ? null : o))} />}
      {over?.folders && <FoldersPage opening={over.folders} me={person} onClose={() => { const was = over; setOver((o) => (o === was ? null : o)); }} />}
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
    {moving && <div className="splash moving" role="status" aria-busy="true"><span className="spinner" /></div>}
  </>);
}
