// CHESS, THE RULES AND THE LETTERS (iOS MTChessRules, MTChessWire, MTChessGame): one owner of the rules, independent of the
// screen, the transport and the clock; a game is replayed from the pair's letters alone, so both machines hold one board.
// NO COINS IN A CHESS LETTER (iOS MTChessWire, the author's word 29.10.2026 19:31 UTC): a move names no coin, an invitation no
// stake; a letter of an earlier build that carries them is read without them, so nothing of coins rides or is counted in a game.

const BACK = ["r", "n", "b", "q", "k", "b", "n", "r"];
export const other = (side) => (side === "white" ? "black" : "white");
export const square = (n) => (n >= 0 && n < 64 ? "abcdefgh"[n % 8] + String(Math.floor(n / 8) + 1) : "");
export function index(sq) {
  if (typeof sq !== "string" || sq.length !== 2) return null;
  const f = sq.charCodeAt(0) - 97, r = sq.charCodeAt(1) - 49;
  return f >= 0 && f < 8 && r >= 0 && r < 8 ? r * 8 + f : null;
}
const same = (a, b) => !!a && !!b && a.side === b.side && a.kind === b.kind;
export const uci = (m) => square(m.from) + square(m.to) + (m.promotion || "");
export function parseMove(word) {
  if (typeof word !== "string" || (word.length !== 4 && word.length !== 5)) return null;
  const from = index(word.slice(0, 2)), to = index(word.slice(2, 4));
  if (from == null || to == null) return null;
  if (word.length === 5 && !"qrbn".includes(word[4])) return null;
  return { from, to, promotion: word.length === 5 ? word[4] : null };
}
const sameMove = (a, b) => a.from === b.from && a.to === b.to && (a.promotion || null) === (b.promotion || null);

/** THE POSITION (iOS MTChessPosition): the board, the side to move, the castling rooks, the en-passant square, the halfmoves. */
export class Position {
  constructor(src) {
    if (src) { Object.assign(this, src, { board: [...src.board], castling: new Set(src.castling) }); return; }
    this.board = Array(64).fill(null);
    for (let f = 0; f < 8; f++) {
      this.board[f] = { side: "white", kind: BACK[f] };
      this.board[8 + f] = { side: "white", kind: "p" };
      this.board[48 + f] = { side: "black", kind: "p" };
      this.board[56 + f] = { side: "black", kind: BACK[f] };
    }
    this.turn = "white"; this.castling = new Set([0, 7, 56, 63]); this.enPassant = null; this.halfmoves = 0; this.ply = 0;
  }
  piece(n) { return n >= 0 && n < 64 ? this.board[n] : null; }
  checked(side) {
    const king = this.board.findIndex((p) => same(p, { side, kind: "k" }));
    return king < 0 ? true : this.attacked(king, other(side));
  }
  attacked(target, side) {
    const tf = target % 8, tr = Math.floor(target / 8);
    for (let from = 0; from < 64; from++) {
      const p = this.board[from];
      if (!p || p.side !== side) continue;
      const df = tf - (from % 8), dr = tr - Math.floor(from / 8);
      if (p.kind === "p") { if (Math.abs(df) === 1 && dr === (side === "white" ? 1 : -1)) return true; }
      else if (p.kind === "n") { if (Math.abs(df) * Math.abs(dr) === 2) return true; }
      else if (p.kind === "k") { if (Math.max(Math.abs(df), Math.abs(dr)) === 1) return true; }
      else {
        if (df === 0 && dr === 0) continue;
        const diagonal = Math.abs(df) === Math.abs(dr), straight = df === 0 || dr === 0;
        if (!((p.kind !== "r" && diagonal) || (p.kind !== "b" && straight))) continue;
        const sf = Math.sign(df), sr = Math.sign(dr);
        let f = (from % 8) + sf, r = Math.floor(from / 8) + sr, clear = true;
        while (f !== tf || r !== tr) { if (this.board[r * 8 + f]) { clear = false; break; } f += sf; r += sr; }
        if (clear) return true;
      }
    }
    return false;
  }
  legalMoves(source = null) {
    const out = [];
    for (let from = 0; from < 64; from++) {
      if (source != null && from !== source) continue;
      const p = this.board[from];
      if (!p || p.side !== this.turn) continue;
      for (const m of this.candidates(from, p)) if (!this.unchecked(m).checked(this.turn)) out.push(m);
    }
    return out;
  }
  candidates(from, p) {
    const out = [], file = from % 8, rank = Math.floor(from / 8);
    const add = (f, r) => {
      if (f < 0 || f > 7 || r < 0 || r > 7) return;
      const to = r * 8 + f, there = this.board[to];
      if ((there && there.side === p.side) || (there && there.kind === "k")) return;
      if (p.kind === "p" && (r === 0 || r === 7)) for (const k of ["q", "r", "b", "n"]) out.push({ from, to, promotion: k });
      else out.push({ from, to, promotion: null });
    };
    if (p.kind === "p") {
      const d = p.side === "white" ? 1 : -1, next = rank + d;
      if (next >= 0 && next < 8) {
        if (!this.board[next * 8 + file]) {
          add(file, next);
          if (rank === (p.side === "white" ? 1 : 6) && !this.board[(rank + 2 * d) * 8 + file]) add(file, rank + 2 * d);
        }
        for (const f of [file - 1, file + 1]) {
          if (f < 0 || f > 7) continue;
          const to = next * 8 + f, there = this.board[to];
          if (there && there.side === other(p.side)) add(f, next);
          else if (to === this.enPassant && !there && same(this.board[rank * 8 + f], { side: other(p.side), kind: "p" })) add(f, next);
        }
      }
    } else if (p.kind === "n") {
      for (const [df, dr] of [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]) add(file + df, rank + dr);
    } else if (p.kind === "k") {
      for (let df = -1; df <= 1; df++) for (let dr = -1; dr <= 1; dr++) if (df || dr) add(file + df, rank + dr);
      const base = p.side === "white" ? 0 : 56;
      if (from === base + 4 && !this.checked(p.side)) {
        for (const [rook, landing, gaps] of [[base + 7, base + 6, [5, 6]], [base, base + 2, [1, 2, 3]]]) {
          if (!this.castling.has(rook) || !same(this.board[rook], { side: p.side, kind: "r" }) || !gaps.every((g) => !this.board[base + g])) continue;
          const transit = from + (landing > from ? 1 : -1);   // the transit square, the king moved off its own
          if (!this.unchecked({ from, to: transit, promotion: null }).checked(p.side)) add(landing % 8, rank);
        }
      }
    } else {
      const diagonal = [[1, 1], [1, -1], [-1, 1], [-1, -1]], straight = [[1, 0], [-1, 0], [0, 1], [0, -1]];
      const dirs = p.kind === "b" ? diagonal : p.kind === "r" ? straight : [...diagonal, ...straight];
      for (const [df, dr] of dirs) {
        let f = file + df, r = rank + dr;
        while (f >= 0 && f < 8 && r >= 0 && r < 8) { add(f, r); if (this.board[r * 8 + f]) break; f += df; r += dr; }
      }
    }
    return out;
  }
  applying(m) { return this.legalMoves(m.from).some((x) => sameMove(x, m)) ? this.unchecked(m) : null; }
  unchecked(m) {
    const next = new Position(this), p = this.piece(m.from);
    if (!p || m.to < 0 || m.to > 63) return next;
    const capture = !!this.board[m.to] || (p.kind === "p" && m.to === this.enPassant);
    next.board[m.from] = null;
    if (p.kind === "p" && m.to === this.enPassant && !this.board[m.to]) next.board[m.to + (p.side === "white" ? -8 : 8)] = null;
    next.board[m.to] = { side: p.side, kind: m.promotion || p.kind };
    if (p.kind === "k") {
      const base = p.side === "white" ? 0 : 56;
      next.castling.delete(base); next.castling.delete(base + 7);
      if (Math.abs(m.to - m.from) === 2) {
        const rook = m.to > m.from ? base + 7 : base;
        next.board[(m.to + m.from) / 2] = next.board[rook]; next.board[rook] = null;
      }
    }
    next.castling.delete(m.from); next.castling.delete(m.to);
    next.enPassant = p.kind === "p" && Math.abs(m.to - m.from) === 16 ? (m.to + m.from) / 2 : null;
    next.halfmoves = p.kind === "p" || capture ? 0 : this.halfmoves + 1;
    next.ply = this.ply + 1; next.turn = other(this.turn);
    return next;
  }
  notation(m) {
    const legal = this.legalMoves(), p = this.board[m.from];
    if (!p || !legal.some((x) => sameMove(x, m))) return null;
    const next = this.unchecked(m);
    let word = "";
    if (p.kind === "k" && Math.abs(m.to - m.from) === 2) word = m.to > m.from ? "O-O" : "O-O-O";
    else {
      const capture = !!this.board[m.to] || (p.kind === "p" && m.to === this.enPassant);
      if (p.kind !== "p") {
        word = p.kind.toUpperCase();
        const rivals = legal.filter((x) => x.to === m.to && x.from !== m.from && this.board[x.from]?.kind === p.kind);
        if (rivals.length) {
          if (!rivals.some((x) => x.from % 8 === m.from % 8)) word += square(m.from)[0];
          else if (!rivals.some((x) => Math.floor(x.from / 8) === Math.floor(m.from / 8))) word += String(Math.floor(m.from / 8) + 1);
          else word += square(m.from);
        }
      } else if (capture) word += square(m.from)[0];
      if (capture) word += "x";
      word += square(m.to);
      if (m.promotion) word += "=" + m.promotion.toUpperCase();
    }
    if (next.checked(next.turn)) word += next.legalMoves().length ? "+" : "#";
    return word;
  }
  get repetitionKey() {
    const pieces = this.board.map((p) => (p ? (p.side === "white" ? p.kind.toUpperCase() : p.kind) : ".")).join("");
    const ep = this.enPassant != null && this.legalMoves().some((x) => x.to === this.enPassant && this.board[x.from]?.kind === "p") ? this.enPassant : null;
    return pieces + this.turn + [...this.castling].sort((a, b) => a - b).join(",") + ":" + (ep == null ? "-" : String(ep));
  }
  get deadMaterial() {
    const men = [];
    this.board.forEach((p, i) => { if (p && p.kind !== "k") men.push([i, p]); });
    if (!men.length) return true;
    if (men.length === 1) return men[0][1].kind === "b" || men[0][1].kind === "n";
    return men.every(([, p]) => p.kind === "b") && new Set(men.map(([i]) => (Math.floor(i / 8) + (i % 8)) % 2)).size === 1;
  }
  matingMaterial(side) {
    const own = this.board.filter((p) => p && p.side === side && p.kind !== "k");
    if (!own.length || this.deadMaterial) return false;
    const opponent = this.board.filter((p) => p && p.side !== side && p.kind !== "k");
    if (!opponent.length && own.length === 1 && (own[0].kind === "b" || own[0].kind === "n")) return false;
    return true;
  }
}

// ── THE LETTER (iOS MTChessLetter) ─────────────────────────────────────────────────────────────────────────────
export const LINK = "montana://chess/1/";
export const TIME_CONTROLS = [0, 300, 600, 900, 1800];
const LONGEST_TURN = 86400000;
const KINDS = ["invite", "accept", "decline", "move", "resign", "draw", "claim", "timeout", "end"];
const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
export const onTurn = (l) => ["move", "draw", "claim", "timeout"].includes(l.kind);
export const isStep = (l) => l.kind !== "invite";

const b64 = (s) => btoa(String.fromCharCode(...new TextEncoder().encode(s))).replace(/\+/g, "-").replace(/\//g, "_");
const unb64 = (s) => new TextDecoder().decode(Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0)));

/** The letter's text: «♟ » and the title, then the link with the letter's JSON (iOS text(title:)). */
export function letterText(l, title) {
  const o = {};
  for (const k of ["game", "id", "parent", "kind", "at", "move", "seconds", "offerDraw", "spent", "end"]) if (l[k] != null) o[k] = l[k];
  return "♟ " + title + "\n" + LINK + b64(JSON.stringify(o));
}

/** A letter read from its text, as iOS parses it -- a frame and a letter both checked; null when it is no game's. */
export function parseLetter(text) {
  if (typeof text !== "string" || !text.startsWith("♟ ") || new TextEncoder().encode(text).length > 2048) return null;
  const line = text.split("\n").pop();
  if (!line.startsWith(LINK)) return null;
  let l;
  try { l = JSON.parse(unb64(line.slice(LINK.length))); } catch { return null; }
  if (!l || typeof l !== "object" || !KINDS.includes(l.kind) || typeof l.game !== "string" || typeof l.id !== "string" || typeof l.parent !== "string") return null;
  if (!UUID.test(l.game) || !UUID.test(l.id) || (l.parent && !UUID.test(l.parent))) return null;
  if (!Number.isInteger(l.at) || l.at < 0 || l.at > 32503680000000) return null;
  if (l.move != null && (typeof l.move !== "string" || l.move.length > 5)) return null;
  if (l.spent != null && !(onTurn(l) && Number.isInteger(l.spent) && l.spent >= 0 && l.spent <= LONGEST_TURN)) return null;
  if (l.end != null && (l.kind === "invite" || l.kind === "accept" || !(l.end.moves >= 0 && l.end.moves <= 10000))) return null;
  delete l.coins; delete l.stake;   // an earlier build's pot fields, read without them (iOS MTChessWire: no coins in a letter)
  if (l.kind === "invite") {
    if (l.id !== l.game || l.parent !== "" || !TIME_CONTROLS.includes(l.seconds) || l.move != null || l.offerDraw != null) return null;
  } else {
    if (l.id === l.game || !l.parent || l.seconds != null) return null;
    if (l.kind !== "move" && l.offerDraw != null) return null;
    if (l.kind !== "move" && l.kind !== "claim" && l.move != null) return null;
  }
  return l;
}

// ── THE GAME (iOS MTChessGame) ─────────────────────────────────────────────────────────────────────────────────
export const finished = (status) => status !== "invited" && status !== "playing";

/** A GAME REPLAYED FROM ITS LETTERS (iOS MTChessGame.init): the inviter plays white; each letter is applied to the one before
 *  it, by its side; an end closes the game over whatever crossed it, then a resignation; two letters of one parent are a
 *  conflict; a letter whose parent has not come is held, never guessed. */
export function replay(entries, game) {
  const relevant = entries.filter((e) => e.letter.game === game);
  const root = relevant.find((e) => e.letter.kind === "invite");
  if (!root || root.letter.id !== game || root.letter.parent !== "" || !TIME_CONTROLS.includes(root.letter.seconds)) return null;
  let g = {
    id: game, whiteIsMine: root.mine, seconds: root.letter.seconds, status: "invited", position: new Position(), moves: [], notation: [],
    last: root.letter, whiteMs: root.letter.seconds * 1000, blackMs: root.letter.seconds * 1000, drawOfferedBy: null,
    repetitions: {}, waitingForHistory: false,
  };
  g.repetitions[g.position.repetitionKey] = 1;
  const unique = new Map();
  for (const e of relevant) {
    const prev = unique.get(e.letter.id);
    if (prev && (JSON.stringify(prev.letter) !== JSON.stringify(e.letter) || prev.mine !== e.mine)) return { ...g, status: "conflict" };
    unique.set(e.letter.id, e);
  }
  const children = new Map();
  for (const e of unique.values()) {
    if (e.letter.id === game) continue;
    if (!children.has(e.letter.parent)) children.set(e.letter.parent, []);
    children.get(e.letter.parent).push(e);
  }
  const visited = new Set([game]);
  while (!finished(g.status)) {
    const possible = (children.get(g.last.id) || []).map((e) => apply(g, e)).filter(Boolean);
    const endings = possible.filter((x) => x.last.kind === "end").sort((a, b) => (a.last.id < b.last.id ? -1 : 1));
    const concessions = possible.filter((x) => x.last.kind === "resign").sort((a, b) => (a.last.id < b.last.id ? -1 : 1));
    const conceding = new Set(concessions.map((x) => unique.get(x.last.id)?.mine));
    if (!endings.length && conceding.size > 1) return { ...g, status: "drawn" };
    const next = endings[0] || concessions[0] || (possible.length === 1 ? possible[0] : null);
    if (!next) { if (possible.length > 1) g = { ...g, status: "conflict" }; break; }
    if (visited.has(next.last.id)) { g = { ...g, status: "conflict" }; break; }
    visited.add(next.last.id);
    g = next;
  }
  if (!finished(g.status)) {
    const stray = [...unique.values()].filter((e) => e.letter.kind === "end").sort((a, b) => (a.letter.id < b.letter.id ? -1 : 1))[0];
    if (stray) g = { ...g, status: "ended", last: stray.letter };
  }
  g.waitingForHistory = g.status !== "ended" && [...unique.values()].some((e) => e.letter.kind !== "invite" && !unique.has(e.letter.parent));
  return g;
}

const held = (g, side) => (side === "white" ? g.whiteMs : g.blackMs);
export const mySide = (g) => (g.whiteIsMine ? "white" : "black");
export const running = (g) => (g.seconds !== 0 && g.status === "playing" ? g.position.turn : null);
export const canClaimDraw = (g) => g.position.halfmoves >= 100 || (g.repetitions[g.position.repetitionKey] || 0) >= 3;

/** One letter applied (iOS apply): the game one letter later, or null when the rules refuse it. */
export function apply(g, entry) {
  const ev = entry.letter, actor = entry.mine === g.whiteIsMine ? "white" : "black";
  if (ev.parent !== g.last.id || ev.at < g.last.at) return null;
  const n = { ...g, repetitions: { ...g.repetitions }, moves: [...g.moves], notation: [...g.notation] };
  const win = (side) => { n.status = side === "white" ? "whiteWon" : "blackWon"; };
  if (ev.kind === "end") { n.status = "ended"; n.last = ev; return n; }
  if (g.status === "invited") {
    if (!((actor === "black" && (ev.kind === "accept" || ev.kind === "decline")) || (actor === "white" && ev.kind === "decline"))) return null;
    n.status = ev.kind === "accept" ? "playing" : "declined"; n.last = ev; return n;
  }
  if (g.status !== "playing") return null;
  if (ev.kind === "resign") {
    if (g.position.matingMaterial(other(actor))) win(other(actor)); else n.status = "drawn";
    n.last = ev; return n;
  }
  if (actor !== g.position.turn) return null;
  const time = held(g, actor) - (ev.spent ?? Math.max(0, ev.at - g.last.at));
  if (ev.kind === "timeout") {
    if (!(g.seconds > 0 && time <= 0)) return null;
    if (actor === "white") n.whiteMs = 0; else n.blackMs = 0;
    if (g.position.matingMaterial(other(actor))) win(other(actor)); else n.status = "drawn";
    n.last = ev; return n;
  }
  if (!(g.seconds === 0 || time > 0)) return null;
  if (ev.kind === "draw") {
    if (g.drawOfferedBy !== other(actor)) return null;
    n.status = "drawn"; n.last = ev; return n;
  }
  if (ev.kind === "claim") {
    let valid = canClaimDraw(g);
    const m = ev.move ? parseMove(ev.move) : null, after = m ? g.position.applying(m) : null;
    if (after) valid = after.halfmoves >= 100 || (g.repetitions[after.repetitionKey] || 0) >= 2;
    if (!valid) return null;
    n.status = "drawn"; n.last = ev; return n;
  }
  const m = ev.kind === "move" && ev.move ? parseMove(ev.move) : null;
  const word = m && g.position.notation(m), after = m && g.position.applying(m);
  if (!m || !word || !after) return null;
  if (g.seconds > 0) { if (actor === "white") n.whiteMs = time; else n.blackMs = time; }
  n.position = after; n.moves.push(m); n.notation.push(word);
  n.drawOfferedBy = ev.offerDraw === true ? actor : null;
  n.last = ev;
  const key = after.repetitionKey;
  n.repetitions[key] = (n.repetitions[key] || 0) + 1;
  if (!after.legalMoves().length) { if (after.checked(after.turn)) win(actor); else n.status = "drawn"; }
  else if (after.deadMaterial || after.halfmoves >= 150 || n.repetitions[key] >= 5) n.status = "drawn";
  return n;
}

/** THE PAIR'S ONE GAME (iOS current): the game of the newest invitation, by its stamp, then its name. */
export function current(entries) {
  const invites = entries.map((e) => e.letter).filter((l) => l.kind === "invite");
  invites.sort((a, b) => (a.at !== b.at ? a.at - b.at : a.id < b.id ? -1 : 1));
  return invites.length ? invites[invites.length - 1].game : null;
}

/** A game a newer invitation replaced is over (iOS replaced). */
export const replaced = (g, cur) => (g && cur && cur !== g.id && !finished(g.status) ? { ...g, status: "ended", waitingForHistory: false } : g);

/** A side's time with the running turn taken off (iOS remaining). */
export function remaining(g, side, elapsed) {
  return running(g) !== side ? held(g, side) : Math.max(0, held(g, side) - Math.max(0, elapsed));
}

const fresh = () => crypto.randomUUID().toLowerCase();

/** The invitation of a new game (iOS MTChessSend.invite): I play white; seconds -- the clock, 0 for none. */
export function invitation(seconds, at = Date.now()) {
  const id = fresh();
  return { game: id, id, parent: "", kind: "invite", at, seconds };
}

/** THE LETTER OF AN ACTION, JUDGED BEFORE IT LEAVES (iOS action): null when the replay would refuse it; a letter on its
 *  sender's turn carries the turn as the sender measured it, and the closing letter names how the game ended. */
export function action(g, kind, { at = Date.now(), move = null, offeringDraw = false, spent = null, mine = true } = {}) {
  if ((kind !== "end" && g.waitingForHistory) || finished(g.status)) return null;
  const ev = { game: g.id, id: fresh(), parent: g.last.id, kind, at: Math.max(g.last.at, at) };
  if (move) ev.move = move;
  if (kind === "move") ev.offerDraw = !!offeringDraw;
  if (g.seconds !== 0 && onTurn(ev) && spent != null) ev.spent = Math.min(Math.max(0, Math.round(spent)), LONGEST_TURN);
  const next = apply(g, { letter: ev, mine });   // the training game's engine acts as the side that is not mine
  if (!next) return null;
  if (finished(next.status)) ev.end = ending(next, mine === g.whiteIsMine ? "white" : "black", kind);
  return ev;
}

function ending(g, actor, kind) {
  const outcome = g.status === "whiteWon" ? (actor === "white" ? "won" : "lost") : g.status === "blackWon" ? (actor === "black" ? "won" : "lost")
    : g.status === "declined" ? "declined" : g.status === "ended" ? "ended" : "drawn";
  let cause;
  if (kind === "decline") cause = actor === "white" ? "withdrawn" : "declined";
  else if (kind === "resign") cause = "resign";
  else if (kind === "timeout") cause = "time";
  else if (kind === "draw") cause = "agreement";
  else if (kind === "claim") cause = "claim";
  else if (kind === "end") cause = "ended";
  else if (!g.position.legalMoves().length) cause = g.position.checked(g.position.turn) ? "mate" : "stalemate";
  else if (g.position.deadMaterial) cause = "material";
  else if (g.position.halfmoves >= 150) cause = "moves";
  else cause = "repetition";
  return { outcome, cause, moves: g.moves.length };
}

/** THE PAIR'S SCORE (iOS MTChessScore): a win to the side that won, a draw to both. */
export function score(games) {
  const s = { mine: 0, theirs: 0, drawn: 0 };
  for (const g of games) {
    if (g.status === "whiteWon") g.whiteIsMine ? s.mine++ : s.theirs++;
    else if (g.status === "blackWon") g.whiteIsMine ? s.theirs++ : s.mine++;
    else if (g.status === "drawn") s.drawn++;
  }
  return s;
}

/** Every game of a pair, replayed, the current one named (iOS ofPair). */
export function games(letters) {
  const entries = letters.map((x) => ({ letter: parseLetter(x.text), mine: x.mine, row: x })).filter((e) => e.letter);
  const cur = current(entries);
  const ids = [...new Set(entries.map((e) => e.letter.game))];
  const all = ids.map((id) => replaced(replay(entries, id), cur)).filter(Boolean);
  return { entries, current: cur, games: all, game: all.find((g) => g.id === cur) || null };
}
