// THE MACHINE'S OWN OPPONENT (iOS MTChessEngine): a search over its own compact board -- material and the widely published
// placement tables, negamax with alpha-beta, captures followed until the position is quiet -- whose depth, time and bounded
// error are set by the level: a weak level plays plausible moves, a strong one its best. The rules owner (Position) names the
// legal moves at the root -- castling, en passant and every promotion; below the root the search walks a faster form of the
// same rules (castling and en passant at the root only, a promotion below it to a queen). Nothing leaves the machine.
import { Position, uci } from "./chess-core.js";

export const LEVELS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const PLANS = {
  1: [1, false, 400, 0.3], 2: [1, true, 250, 0.4], 3: [2, true, 150, 0.6], 4: [2, true, 80, 0.8], 5: [3, true, 45, 1.0],
  6: [3, true, 20, 1.2], 7: [4, true, 8, 1.6], 8: [4, true, 0, 2.0], 9: [5, true, 0, 3.0], 10: [6, true, 0, 4.0],
};
const plan = (level) => { const [depth, quiet, error, budget] = PLANS[Math.min(Math.max(level, 1), 10)]; return { depth, quiet, error, budget }; };
const CODE = { p: 1, n: 2, b: 3, r: 4, q: 5, k: 6 };
const WORTH = [0, 100, 320, 330, 500, 900, 20000];
const KNIGHT = [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]];
const KING = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]];
const STRAIGHT = [[1, 0], [-1, 0], [0, 1], [0, -1]];
const DIAGONAL = [[1, 1], [1, -1], [-1, 1], [-1, -1]];
const QUEEN = [...STRAIGHT, ...DIAGONAL];
const SLIDERS = [[STRAIGHT, 4], [DIAGONAL, 3]];
const INFINITY = 1000000, MATE = 100000;

const T = {
  pawn: [0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, 10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5,
    0, 0, 0, 20, 20, 0, 0, 0, 5, -5, -10, 0, 0, -10, -5, 5, 5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0],
  knight: [-50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30, -30, 5, 15, 20, 20, 15, 5, -30,
    -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30, -40, -20, 0, 5, 5, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50],
  bishop: [-20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 10, 10, 5, 0, -10, -10, 5, 5, 10, 10, 5, 5, -10,
    -10, 0, 10, 10, 10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10, -10, 5, 0, 0, 0, 0, 5, -10, -20, -10, -10, -10, -10, -10, -10, -20],
  rook: [0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5,
    -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0],
  queen: [-20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10, -5, 0, 5, 5, 5, 5, 0, -5,
    0, 0, 5, 5, 5, 5, 0, -5, -10, 5, 5, 5, 5, 5, 0, -10, -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20],
  kingEarly: [-30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30, -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20, -20, -10,
    20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10, 30, 20],
  kingLate: [-50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, -30, -10, 20, 30, 30, 20, -10, -30,
    -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30,
    -30, -30, 0, 0, 0, 0, -30, -30, -50, -30, -30, -30, -30, -30, -30, -50],
};
const PLACEMENT = [[], T.pawn, T.knight, T.bishop, T.rook, T.queen, T.kingEarly];

/** The compact board (iOS Board): a signed code a square, white positive, square 0 = a1. */
class Board {
  constructor(src) {
    if (src instanceof Board) { this.cells = src.cells.slice(); this.side = src.side; this.whiteKing = src.whiteKing; this.blackKing = src.blackKing; return; }
    this.cells = new Int8Array(64);
    for (let s = 0; s < 64; s++) { const p = src.piece(s); if (p) this.cells[s] = CODE[p.kind] * (p.side === "white" ? 1 : -1); }
    this.side = src.turn === "white" ? 1 : -1;
    this.whiteKing = this.cells.indexOf(6); this.blackKing = this.cells.indexOf(-6);
  }
  child(m) {
    const next = new Board(this), piece = this.cells[m.from], kind = Math.abs(piece);
    if (kind === 1 && m.from % 8 !== m.to % 8 && this.cells[m.to] === 0) next.cells[m.to - 8 * this.side] = 0;
    if (kind === 6 && Math.abs(m.to - m.from) === 2) {
      const rook = m.to > m.from ? m.from + 3 : m.from - 4;
      next.cells[(m.from + m.to) / 2] = next.cells[rook]; next.cells[rook] = 0;
    }
    next.cells[m.to] = m.promotion ? CODE[m.promotion] * this.side : piece;
    next.cells[m.from] = 0;
    if (piece === 6) next.whiteKing = m.to; else if (piece === -6) next.blackKing = m.to;
    next.side = -this.side;
    return next;
  }
  make(st) {
    const piece = this.cells[st.from], taken = this.cells[st.to];
    this.cells[st.to] = st.promote === 0 ? piece : st.promote * this.side;
    this.cells[st.from] = 0;
    if (piece === 6) this.whiteKing = st.to; else if (piece === -6) this.blackKing = st.to;
    this.side = -this.side;
    return taken;
  }
  unmake(st, taken) {
    this.side = -this.side;
    const piece = st.promote === 0 ? this.cells[st.to] : this.side;
    this.cells[st.from] = piece; this.cells[st.to] = taken;
    if (piece === 6) this.whiteKing = st.from; else if (piece === -6) this.blackKing = st.from;
  }
  get inCheck() { return this.attacked(this.side === 1 ? this.whiteKing : this.blackKing, -this.side); }
  get moverExposed() { return this.attacked(this.side === 1 ? this.blackKing : this.whiteKing, this.side); }
  attacked(sq, by) {
    const file = sq % 8, rank = Math.floor(sq / 8), behind = rank - by, c = this.cells;
    if (behind >= 0 && behind < 8) {
      if (file > 0 && c[behind * 8 + file - 1] === by) return true;
      if (file < 7 && c[behind * 8 + file + 1] === by) return true;
    }
    for (const [df, dr] of KNIGHT) { const f = file + df, r = rank + dr; if (f >= 0 && f < 8 && r >= 0 && r < 8 && c[r * 8 + f] === 2 * by) return true; }
    for (const [df, dr] of KING) { const f = file + df, r = rank + dr; if (f >= 0 && f < 8 && r >= 0 && r < 8 && c[r * 8 + f] === 6 * by) return true; }
    for (const [rays, slider] of SLIDERS) {
      for (const [df, dr] of rays) {
        let f = file + df, r = rank + dr;
        while (f >= 0 && f < 8 && r >= 0 && r < 8) {
          const p = c[r * 8 + f];
          if (p !== 0) { if (p === slider * by || p === 5 * by) return true; break; }
          f += df; r += dr;
        }
      }
    }
    return false;
  }
  steps(capturesOnly) {
    const out = [], c = this.cells, side = this.side;
    const enemy = (t) => t !== 0 && (t > 0) !== (side > 0);
    for (let from = 0; from < 64; from++) {
      const piece = c[from];
      if (piece === 0 || (piece > 0) !== (side > 0)) continue;
      const kind = Math.abs(piece), file = from % 8, rank = Math.floor(from / 8);
      const add = (to, promote = 0) => {
        const target = c[to], gain = target === 0 ? 0 : WORTH[Math.abs(target)] * 16 - kind;
        out.push({ from, to, promote, order: gain + (promote === 0 ? 0 : 8000) });
      };
      if (kind === 1) {
        const ahead = rank + side;
        if (ahead < 0 || ahead > 7) continue;
        const promote = ahead === 0 || ahead === 7 ? 5 : 0;
        if (c[ahead * 8 + file] === 0 && (!capturesOnly || promote)) {
          add(ahead * 8 + file, promote);
          const two = rank + 2 * side;
          if (!capturesOnly && rank === (side === 1 ? 1 : 6) && c[two * 8 + file] === 0) add(two * 8 + file);
        }
        for (const df of [-1, 1]) { const f = file + df; if (f >= 0 && f < 8 && enemy(c[ahead * 8 + f])) add(ahead * 8 + f, promote); }
      } else if (kind === 2 || kind === 6) {
        for (const [df, dr] of kind === 2 ? KNIGHT : KING) {
          const f = file + df, r = rank + dr;
          if (f < 0 || f > 7 || r < 0 || r > 7) continue;
          const t = c[r * 8 + f];
          if (t === 0 ? !capturesOnly : enemy(t)) add(r * 8 + f);
        }
      } else {
        for (const [df, dr] of kind === 3 ? DIAGONAL : kind === 4 ? STRAIGHT : QUEEN) {
          let f = file + df, r = rank + dr;
          while (f >= 0 && f < 8 && r >= 0 && r < 8) {
            const t = c[r * 8 + f];
            if (t !== 0) { if (enemy(t)) add(r * 8 + f); break; }
            if (!capturesOnly) add(r * 8 + f);
            f += df; r += dr;
          }
        }
      }
    }
    return out.sort((a, b) => b.order - a.order);
  }
  evaluate() {
    let officers = 0;
    for (const p of this.cells) { const k = Math.abs(p); if (p !== 0 && k !== 1 && k !== 6) officers += WORTH[k]; }
    const late = officers <= 2600;
    let score = 0;
    for (let s = 0; s < 64; s++) {
      const p = this.cells[s];
      if (p === 0) continue;
      const kind = Math.abs(p), white = p > 0;
      const table = kind === 6 && late ? T.kingLate : PLACEMENT[kind];
      const value = WORTH[kind] + table[white ? s ^ 56 : s];
      score += white ? value : -value;
    }
    return score * this.side;
  }
}

class Search {
  constructor(quiet, deadline) { this.quiet = quiet; this.deadline = deadline; this.timed = false; this.aborted = false; this.nodes = 0; }
  expired() {
    this.nodes++;
    if (this.timed && (this.nodes & 1023) === 0 && Date.now() > this.deadline) this.aborted = true;
    return this.aborted;
  }
  negamax(board, depth, alphaIn, beta, ply) {
    if (this.expired()) return 0;
    if (depth <= 0) return this.quiet ? this.quiesce(board, alphaIn, beta, 0) : board.evaluate();
    let alpha = alphaIn, legal = false;
    for (const st of board.steps(false)) {
      const taken = board.make(st);
      if (board.moverExposed) { board.unmake(st, taken); continue; }
      legal = true;
      const score = -this.negamax(board, depth - 1, -beta, -alpha, ply + 1);
      board.unmake(st, taken);
      if (this.aborted) return 0;
      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }
    if (!legal) return board.inCheck ? -MATE + ply : 0;   // mated, the sooner the worse, or stalemated
    return alpha;
  }
  quiesce(board, alphaIn, beta, depth) {
    if (this.expired()) return 0;
    const stand = board.evaluate();
    if (stand >= beta) return beta;
    let alpha = Math.max(alphaIn, stand);
    if (depth >= 8) return alpha;
    for (const st of board.steps(true)) {
      const taken = board.make(st);
      if (board.moverExposed) { board.unmake(st, taken); continue; }
      const score = -this.quiesce(board, -beta, -alpha, depth + 1);
      board.unmake(st, taken);
      if (this.aborted) return 0;
      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }
    return alpha;
  }
}

/** The engine's move in this position, or none when there is no legal move (iOS reply). */
export function reply(position, level) {
  const legal = position.legalMoves();
  if (!legal.length) return null;
  if (legal.length === 1) return legal[0];
  const p = plan(level), root = new Board(position), children = legal.map((m) => root.child(m));
  const search = new Search(p.quiet, Date.now() + p.budget * 1000);
  let order = legal.map((_, i) => i), scores = legal.map(() => 0);
  for (let depth = 1; depth <= p.depth; depth++) {
    search.timed = depth !== 1;   // the first depth always completes: there is always a move to give
    const round = legal.map(() => -INFINITY);
    let best = -INFINITY;
    for (const i of order) {
      const board = new Board(children[i]);
      const floor = best === -INFINITY ? -INFINITY : best - p.error - 1;   // a move worse than the error allows needs no exact score
      const score = -search.negamax(board, depth - 1, -INFINITY, -floor, 1);
      if (search.aborted) break;
      round[i] = score;
      best = Math.max(best, score);
    }
    if (search.aborted) break;
    scores = round;
    order = [...order].sort((a, b) => scores[b] - scores[a]);
    if (best >= MATE - 64) break;   // a mate found: no deeper search improves on it
  }
  let chosen = order[0], top = -Infinity;
  for (const i of order) {
    const noisy = scores[i] + (p.error > 0 ? Math.floor(Math.random() * (p.error + 1)) : 0);
    if (noisy > top) { top = noisy; chosen = i; }
  }
  return legal[chosen];
}

/** The engine's move as UCI, from a position sent across a worker's border. */
export function replyFrom(state, level) {
  const m = reply(new Position(state), level);
  return m ? uci(m) : null;
}
