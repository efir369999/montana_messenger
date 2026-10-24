import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { Face, SAVED, chatName, useChanged } from "./Chats.jsx";
import { Page, Section } from "./Settings.jsx";
import { TIME_CONTROLS, action, canClaimDraw, finished, games, invitation, letterText, mySide, parseLetter, remaining, replay, running, score, share, square, uci } from "./chess-core.js";
import { LEVELS } from "./chess-engine.js";

/** THE CHAT'S CLOCK FOR A NEW GAME (iOS MTChessSend.chatClock): ten minutes a side, offered first. */
const CHAT_CLOCK = 600;
/** THE PIECES ARE iOS'S OWN ARTWORK (MTChessPalette.asset: «Chess» + w|b + the kind), kept byte for byte. */
const ART = import.meta.glob("./assets/ios/Chess[wb][kqrbnp].png", { eager: true, import: "default" });
const art = (side, kind) => ART[`./assets/ios/Chess${side === "white" ? "w" : "b"}${kind}.png`];
const Piece = ({ side, kind }) => <img className="chess-art" src={art(side, kind)} alt="" draggable={false} />;
const NAMES = { p: "pawn", n: "knight", b: "bishop", r: "rook", q: "queen", k: "king" };
export const control = (s) => (s === 0 ? t("No clock") : `${s / 60}:00`);
const clock = (ms) => { const s = Math.max(0, Math.floor((ms + 999) / 1000)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`; };
const computerName = (level) => t("Computer, level %@", { "%@": level });

/** A chess letter's line in the list and the banner (iOS MTRowLetter.preview): «♟ Chess». */
export const chessPreview = (text) => (parseLetter(text) ? "♟ " + t("Chess") : null);

/** The invitation's seat and clock, from this side (iOS MTChessWords.seat). */
export const chessSeat = (text, mine) => {
  const l = parseLetter(text);
  return l && l.kind === "invite" ? `${mine ? t("You play white") : t("You play black")} · ${control(l.seconds)}` : null;
};

/** The game's state in words (iOS MTChessWords.status). */
function status(g, computer = false) {
  if (g.waitingForHistory) return t("Waiting for earlier moves");
  switch (g.status) {
    case "invited": return g.whiteIsMine ? t("Waiting for the invitation to be accepted") : t("Chess invitation");
    case "playing":
      if (g.position.checked(g.position.turn)) return t("Check!");
      if (g.position.turn === mySide(g)) return t("Your move");
      return computer ? t("The computer is thinking") : t("Opponent's move");
    case "declined": return t("Invitation declined");
    case "whiteWon": return t("White wins");
    case "blackWon": return t("Black wins");
    case "drawn": return t("Draw");
    case "ended": return t("Game ended");
    default: return t("Conflicting moves — start a new game");
  }
}

const pieceName = (p) => t(`${p.side === "white" ? "White" : "Black"} ${NAMES[p.kind]}`);

// ── THE TRAINING GAME (iOS MTChessComputer): one game with this machine's engine, kept in the very letters a correspondent's
// game is made of, so the one replay judges every move and the end; nothing of it leaves the machine. ──────────────────────
const KEPT = "chess.computer.game";
export function keptComputer() {
  try {
    const k = JSON.parse(localStorage.getItem(KEPT) || "null");
    if (!k || !Array.isArray(k.letters) || k.letters.length !== k.mine.length || !k.letters.length) return null;
    return k;
  } catch { return null; }
}
function keepComputer(k) {
  try { localStorage.setItem(KEPT, JSON.stringify(k)); } catch { /* the game lives while the window does */ }
}
const computerGame = (k) => (k ? replay(k.letters.map((l, i) => ({ letter: l, mine: k.mine[i] })), k.letters[0].game) : null);
let worker = null;
const think = (g, level) => new Promise((done) => {
  worker = worker || new Worker(new URL("./chess-worker.js", import.meta.url), { type: "module" });
  const id = crypto.randomUUID();
  const heard = (e) => { if (e.data.id === id) { worker.removeEventListener("message", heard); done(e.data.move); } };
  worker.addEventListener("message", heard);
  const p = g.position;
  worker.postMessage({ id, level, state: { board: p.board, turn: p.turn, castling: [...p.castling], enPassant: p.enPassant, halfmoves: p.halfmoves, ply: p.ply } });
});

/** THE POT AND WHAT THE GAME GAVE OR TOOK (iOS MTChessCoins.net), one line. */
const potLine = (g, net) => `${t("Pot")}: ${g.stake * (g.accepted ? 2 : 1) + g.mintedMine + g.mintedTheirs}`
  + (net != null && finished(g.status) ? ` · ${net >= 0 ? "+" : "−"}${Math.abs(net)}` : "");

/** A GAME ON ITS BOARD (iOS MTChessGameScreen): with a correspondent -- the pair's one game, replayed from its letters on every
 *  change -- or with the computer; my side at the foot; a tap on my piece shows where it goes, a tap there makes the move;
 *  the clocks, the draw, the resignation, the end; a new game once this one is over. Only the invitation stands in the chat. */
export function ChessBoard({ chat, name, onClose, computer = false }) {
  const [letters, setLetters] = useState(null);
  const [kept, setKept] = useState(() => (computer ? keptComputer() : null));
  const [picked, setPicked] = useState(null);
  const [promoting, setPromoting] = useState(null);   // the moves that wait for their piece
  const [offer, setOffer] = useState(false);
  const [problem, setProblem] = useState(null);
  const [now, setNow] = useState(Date.now());
  const [newClock, setNewClock] = useState(CHAT_CLOCK);
  const [stake, setStake] = useState("");      // the coins each side puts into the pot (iOS MTChessNewGame's stake)
  const [nets, setNets] = useState({});        // a finished pot's game: what it gave or took (iOS MTChessCoins.net)
  const [level, setLevel] = useState(() => keptComputer()?.level || 3);
  const [white, setWhite] = useState(true);
  const [thinking, setThinking] = useState(false);
  const conceded = useRef(null);
  const look = () => (computer ? setKept(keptComputer()) : invoke("chess_letters", { chat }).then(setLetters).catch(() => setLetters([])));
  useEffect(() => { look(); }, [chat, computer]);
  useChanged(() => { if (!computer) look(); });
  useEffect(() => { const id = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(id); }, []);
  const pair = computer ? null : letters ? games(letters) : null;
  // THE POT PAID AT THE END (iOS MTChessCoins.pay): each machine books its own side once, by the game's names
  useEffect(() => {
    if (!pair) return;
    for (const pg of pair.games) {
      const s = share(pg);
      if (s) invoke("chess_settle", { chat, game: pg.id, minted: s.minted, back: s.back, put: s.put })
        .then((net) => setNets((x) => (x[pg.id] === net ? x : { ...x, [pg.id]: net }))).catch(() => {});
    }
  }, [letters]);
  const g = computer ? computerGame(kept) : pair?.game || null;
  const me = g ? mySide(g) : "white";
  const commit = (l, mine) => {
    const k = keptComputer();
    if (!k || !l) return false;
    const next = { ...k, letters: [...k.letters, l], mine: [...k.mine, mine] };
    keepComputer(next); setKept(next);
    return true;
  };
  const send = async (l) => {
    setProblem(null);
    if (!l) { setProblem(t("Not sent")); return; }
    if (computer) commit(l, true);
    else {
      // THE STAKE LEAVES THE BOOK INTO THE POT before the letter does: the inviter's with the invitation, the guest's with the
      // acceptance (iOS MTChessCoins.put); a short balance refuses the letter
      const put = l.kind === "invite" ? l.stake || 0 : l.kind === "accept" && g?.pooled ? g.stake : 0;
      if (put > 0 && !(await invoke("chess_stake", { chat, game: l.game, stake: put }).catch(() => false))) { setProblem(t("Not enough coins")); return; }
      const ok = await invoke("chat_send", { chat, text: letterText(l, t("Chess")) }).then(() => true).catch(() => false);
      if (!ok) setProblem(t("Not sent"));
      look();
    }
    setPicked(null); setPromoting(null);
  };
  // the engine answers when the turn becomes its own, never in the same frame as my move (iOS answerIfDue)
  useEffect(() => {
    if (!computer || !g || thinking || g.status !== "playing" || g.position.turn === me) return;
    setThinking(true);
    const began = Date.now(), last = g.last.id, lvl = kept.level;
    think(g, lvl).then((m) => setTimeout(() => {
      setThinking(false);
      const k = keptComputer(), cur = computerGame(k);
      if (!m || !cur || cur.last.id !== last) return;
      commit(action(cur, "move", { move: m, mine: false }), false);
    }, Math.max(0, 350 - (Date.now() - began))));
  });
  // the running turn began with the game's last letter: its stamp, the node's clock and this one agreeing (iOS MTChessAnchor)
  const elapsed = g ? Math.max(0, now - g.last.at) : 0;
  const mineRunning = !computer && g && running(g) === me;
  // only the owner of a clock concedes it, when its own measure has run out (iOS timeout)
  useEffect(() => {
    if (g && mineRunning && remaining(g, me, elapsed) <= 0 && conceded.current !== g.last.id) {
      conceded.current = g.last.id;
      send(action(g, "timeout", { spent: elapsed }));
    }
  });
  if (!computer && !letters) return null;
  const myTurn = g && g.status === "playing" && !g.waitingForHistory && g.position.turn === me && !thinking;
  const tap = (n) => {
    if (!myTurn) return;
    const p = g.position.piece(n);
    if (picked != null) {
      const moves = g.position.legalMoves(picked).filter((m) => m.to === n);
      if (moves.length > 1) { setPromoting(moves); return; }
      if (moves.length === 1) { move(moves[0]); return; }
    }
    setPicked(p && p.side === me ? n : null);
  };
  const move = (m) => send(action(g, "move", { move: uci(m), offeringDraw: offer, spent: elapsed })).then(() => setOffer(false));
  const start = () => {
    // the person invites when they take white (iOS start): the invitation and the acceptance at once
    const inv = invitation(0);
    const acc = { game: inv.game, id: crypto.randomUUID().toLowerCase(), parent: inv.id, kind: "accept", at: inv.at };
    const k = { level, letters: [inv, acc], mine: [white, !white] };
    keepComputer(k); setKept(k); setPicked(null);
  };
  const takeBack = () => {
    const k = keptComputer();
    const cut = k ? k.letters.map((l, i) => l.kind === "move" && k.mine[i]).lastIndexOf(true) : -1;
    if (cut < 0) return;
    const next = { ...k, letters: k.letters.slice(0, cut), mine: k.mine.slice(0, cut) };
    keepComputer(next); setKept(next); setPicked(null);
  };
  const targets = g && picked != null ? new Set(g.position.legalMoves(picked).map((m) => m.to)) : new Set();
  const rows = [...Array(8).keys()].map((i) => (me === "white" ? 7 - i : i));
  const files = [...Array(8).keys()].map((i) => (me === "white" ? i : 7 - i));
  const s = computer ? null : score(pair.games);
  const open = g && !finished(g.status);
  const theirs = me === "white" ? "black" : "white";
  return (
    <Page title={t("Chess")} onClose={onClose} back>
      <div className="chess-head">
        <span className="chess-name">{computer ? computerName(kept?.level || level) : name}</span>
        <span className="chess-status">{g ? status(g, computer) : computer ? t("Play the computer") : t("Invite a correspondent")}</span>
        {s && <span className="row-caption">{t("Wins \\(a) · Losses \\(b) · Draws \\(c)", { a: s.mine, b: s.theirs, c: s.drawn })}</span>}
      </div>
      {g && g.seconds > 0 && <div className="chess-clock" aria-label={`${t(theirs === "white" ? "White clock" : "Black clock")} ${clock(remaining(g, theirs, elapsed))}`}>{clock(remaining(g, theirs, elapsed))}</div>}
      {g && (
        // THE BOARD (iOS MTChessBoardCanvas): one square of eight by eight equal cells; the last move's squares and the picked one
        // filled with the highlight of their colour, a king in check under red, a move's square a dot when empty and a ring when it
        // takes; the ranks in the first column's corner, the files along the foot -- each in the other square colour
        <div className="chess-board" role="grid" aria-label={t("Live position")}>
          {rows.map((r, ri) => files.map((f, fi) => {
            const n = r * 8 + f, p = g.position.piece(n), dark = (r + f) % 2 === 0;
            const lastMove = g.moves[g.moves.length - 1];
            const lit = picked === n || (lastMove && (lastMove.from === n || lastMove.to === n));
            const check = p && p.kind === "k" && g.position.checked(p.side);
            return (
              <button key={n} className={"chess-square" + (dark ? " dark" : "") + (lit ? " lit" : "") + (check ? " check" : "")
                                         + (targets.has(n) ? (p ? " takes" : " target") : "")}
                      aria-label={square(n) + (p ? " " + pieceName(p) : "")} aria-pressed={picked === n} onClick={() => tap(n)}>
                {p ? <Piece side={p.side} kind={p.kind} /> : null}
                {fi === 0 && <span className="chess-rank">{square(n).slice(1)}</span>}
                {ri === 7 && <span className="chess-file">{square(n).slice(0, 1)}</span>}
              </button>
            );
          }))}
        </div>
      )}
      {g && g.seconds > 0 && <div className="chess-clock mine" aria-label={`${t(me === "white" ? "White clock" : "Black clock")} ${clock(remaining(g, me, elapsed))}`}>{clock(remaining(g, me, elapsed))}</div>}
      {promoting && (
        <Section head={t("Promote pawn")}>
          <div className="chess-promote">
            {promoting.map((m) => (
              <button key={m.promotion} className="glass-mark chess-promote-key" aria-label={pieceName({ side: me, kind: m.promotion })} onClick={() => move(m)}><Piece side={me} kind={m.promotion} /></button>
            ))}
          </div>
        </Section>
      )}
      {problem && <div className="talk-problem">{problem}</div>}
      {!computer && g && g.status === "invited" && (
        <Section>
          {!g.whiteIsMine && <button className="set-row accent" onClick={() => send(action(g, "accept"))}><span className="row-title" style={{ color: "var(--blue)" }}>{t("Accept invitation")}</span></button>}
          <button className="set-row" onClick={() => send(action(g, "decline"))}><span className="row-title red">{g.whiteIsMine ? t("Withdraw invitation") : t("Decline invitation")}</span></button>
        </Section>
      )}
      {g && g.status === "playing" && !g.waitingForHistory && (
        <Section head={t("Game actions")}>
          {!computer && g.drawOfferedBy === theirs && <button className="set-row accent" onClick={() => send(action(g, "draw", { spent: elapsed }))}><span className="row-title" style={{ color: "var(--blue)" }}>{t("Accept draw")}</span></button>}
          {!computer && (
            <button className="set-row" aria-pressed={offer} aria-label={t("Offer draw with next move")} onClick={() => setOffer(!offer)}>
              <span className="row-title">{t("Offer draw with next move")}</span><span className={"pick-tick" + (offer ? " on" : "")}>{offer ? "✓" : ""}</span>
            </button>
          )}
          {canClaimDraw(g) && g.position.turn === me && <button className="set-row" onClick={() => send(action(g, "claim", { spent: elapsed }))}><span className="row-title">{t("Claim draw")}</span></button>}
          {computer && <button className="set-row" disabled={thinking} onClick={takeBack}><span className="row-title">{t("Take back move")}</span></button>}
          <button className="set-row" onClick={() => send(action(g, "resign"))}><span className="row-title red">{t("Resign")}</span></button>
        </Section>
      )}
      {!computer && open && <Section><button className="set-row" onClick={() => send(action(g, "end"))}><span className="row-title red">{t("End game")}</span></button></Section>}
      {!computer && !open && (
        <Section head={t("New game")}>
          <div className="slow-steps" role="radiogroup" aria-label={t("Time control")}>
            {TIME_CONTROLS.map((c) => (
              <button key={c} role="radio" aria-checked={c === newClock} className={"slow-step" + (c === newClock ? " on" : "")} onClick={() => setNewClock(c)}>{control(c)}</button>
            ))}
          </div>
          <label className="set-row"><span className="row-title">{t("Stake")}</span>
            <input className="auto-coins" inputMode="numeric" placeholder="0" value={stake} aria-label={t("Stake")}
                   onChange={(e) => setStake(e.target.value.replace(/\D/g, "").slice(0, 13))} /></label>
          <button className="set-row accent" onClick={() => send(invitation(newClock, Date.now(), Number(stake || 0)))}><span className="row-title" style={{ color: "var(--blue)" }}>{t("Invite a correspondent")}</span></button>
          <div className="post-note">{t("Both players put the stake into the game's pot, and every move adds a coin to it within the same one coin a second. The winner takes the whole pot; a draw gives each their own back.")}</div>
        </Section>
      )}
      {computer && (
        <Section head={t("New game")}>
          <div className="set-row"><span className="row-title">{t("Level")}: {level}</span>
            <input type="range" min={LEVELS[0]} max={LEVELS[LEVELS.length - 1]} value={level} aria-label={t("Level")} onChange={(e) => setLevel(Number(e.target.value))} /></div>
          <div className="slow-steps" role="radiogroup" aria-label={t("New game")}>
            {[[true, "White pieces"], [false, "Black pieces"]].map(([on, word]) => (
              <button key={word} role="radio" aria-checked={white === on} className={"slow-step" + (white === on ? " on" : "")} onClick={() => setWhite(on)}>{t(word)}</button>
            ))}
          </div>
          <button className="set-row accent" onClick={start}><span className="row-title" style={{ color: "var(--blue)" }}>{t("Play the computer")}</span></button>
        </Section>
      )}
      {g && g.pooled && (g.stake > 0 || g.mintedMine + g.mintedTheirs > 0) && (
        <div className="post-note" role="status">{potLine(g, nets[g.id])}</div>
      )}
      {g && g.notation.length > 0 && (
        <Section head={t("Moves")}>
          <div className="chess-moves">{g.notation.map((w, i) => (i % 2 === 0 ? `${i / 2 + 1}. ${w}` : w)).join(" ")}</div>
        </Section>
      )}
    </Page>
  );
}

/** THE CHESS PAGE (iOS MTChessScreen's list): the training game, then every pair's games -- the unfinished first, then by their
 *  last letter -- each opening its board; «Invite a correspondent» chooses whom to play, «Play the computer» plays here. */
export function ChessPane({ query }) {
  const [records, setRecords] = useState(null);
  const [board, setBoard] = useState(null);       // {chat, name} or {computer: true}
  const [choosing, setChoosing] = useState(false);
  const [people, setPeople] = useState([]);
  const look = async () => {
    const rows = (await invoke("chats").catch(() => [])).filter((r) => !r.group && !r.blocked && r.ref !== SAVED);
    setPeople(rows);
    const out = [];
    for (const r of rows) {
      const letters = await invoke("chess_letters", { chat: r.ref }).catch(() => []);
      if (!letters.length) continue;
      for (const g of games(letters).games) out.push({ chat: r.ref, name: chatName(r.name), face: r.face, g });
    }
    out.sort((a, b) => (finished(a.g.status) !== finished(b.g.status) ? (finished(a.g.status) ? 1 : -1) : b.g.last.at - a.g.last.at));
    setRecords(out);
  };
  useEffect(() => { look(); }, []);
  useChanged(look);
  if (board) {
    return <div className="pane-over"><ChessBoard chat={board.chat} name={board.name} computer={!!board.computer} onClose={() => { setBoard(null); look(); }} /></div>;
  }
  const q = query.trim().toLowerCase();
  if (choosing) {
    return (
      <div className="rows">
        <button className="archive-back" onClick={() => setChoosing(false)}><Glyph name="back" size={16} color="var(--blue)" />{t("Chess")}</button>
        {people.filter((r) => !q || chatName(r.name).toLowerCase().includes(q)).map((r) => (
          <div key={r.ref} className="row" role="button" tabIndex={0} aria-label={chatName(r.name)}
               onClick={() => { setChoosing(false); setBoard({ chat: r.ref, name: chatName(r.name) }); }}>
            <Face chat={r.ref} version={r.face} size={48} />
            <div className="words"><div className="top"><span className="name">{chatName(r.name)}</span></div></div>
          </div>
        ))}
        {people.length === 0 && <div className="no-results">{t("No correspondents found")}</div>}
      </div>
    );
  }
  if (!records) return null;
  const shown = records.filter((x) => !q || x.name.toLowerCase().includes(q));
  const kept = keptComputer(), cg = computerGame(kept);
  return (
    <div className="rows">
      <button className="set-row accent chess-invite" onClick={() => setChoosing(true)}>
        <span className="row-title" style={{ color: "var(--blue)" }}>♟ {t("Invite a correspondent")}</span>
      </button>
      <button className="set-row accent chess-invite" onClick={() => setBoard({ computer: true })}>
        <span className="row-title" style={{ color: "var(--blue)" }}>♚ {t("Play the computer")}</span>
      </button>
      {cg && (
        <div className="row" role="button" tabIndex={0} aria-label={`${computerName(kept.level)}, ${status(cg, true)}`} onClick={() => setBoard({ computer: true })}>
          <div className="face chess-cpu">♚</div>
          <div className="words">
            <div className="top"><span className="name">{computerName(kept.level)}</span></div>
            <div className="bottom"><span className="preview">{status(cg, true)}</span></div>
          </div>
        </div>
      )}
      {shown.map((x) => (
        <div key={x.chat + x.g.id} className="row" role="button" tabIndex={0} aria-label={`${x.name}, ${status(x.g)}`}
             onClick={() => setBoard({ chat: x.chat, name: x.name })}>
          <Face chat={x.chat} version={x.face} size={48} />
          <div className="words">
            <div className="top"><span className="name">{x.name}</span></div>
            <div className="bottom"><span className="preview">{status(x.g)}</span></div>
          </div>
        </div>
      ))}
      {shown.length === 0 && !cg && <div className="empty-pane"><div className="empty-text">{t("Invite a correspondent or play the computer.")}</div></div>}
    </div>
  );
}

