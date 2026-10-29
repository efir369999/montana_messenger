// THE CHESS CORE, CHECKED (src/chess-core.js, the port of iOS MTChessRules/MTChessWire/MTChessGame): the rules on known
// positions and a game replayed from the letters of both sides, as each of two machines holds them.
// usage: node tools/chess-check.mjs
import { Position, parseMove, uci, letterText, parseLetter, invitation, action, games, replay, index, LINK } from "../src/chess-core.js";

let failed = 0;
const ok = (cond, what) => { if (!cond) { failed++; console.log("FAIL " + what); } else console.log("ok   " + what); };
const play = (p, ...words) => words.reduce((q, w) => (q ? q.applying(parseMove(w)) : null), p);

// the rules
const start = new Position();
ok(start.legalMoves().length === 20, "twenty moves at the start");
const mate = play(start, "f2f3", "e7e5", "g2g4", "d8h4");
ok(mate && mate.checked("white") && mate.legalMoves().length === 0, "the fool's mate");
ok(start.notation(parseMove("g1f3")) === "Nf3", "notation of a knight's move");
const castle = play(start, "e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6");
ok(castle && castle.legalMoves(index("e1")).some((m) => uci(m) === "e1g1"), "the king may castle short");
const castled = castle.applying(parseMove("e1g1"));
ok(castled.piece(index("f1"))?.kind === "r" && castle.notation(parseMove("e1g1")) === "O-O", "the rook crosses, O-O");
const ep = play(start, "e2e4", "a7a6", "e4e5", "d7d5");
ok(ep && ep.legalMoves(index("e5")).some((m) => uci(m) === "e5d6"), "en passant stands");
ok(ep.applying(parseMove("e5d6")).piece(index("d5")) === null, "en passant takes the pawn beside");
const promo = new Position();
promo.board = Array(64).fill(null);
promo.board[index("a7")] = { side: "white", kind: "p" }; promo.board[index("e1")] = { side: "white", kind: "k" }; promo.board[index("h8")] = { side: "black", kind: "k" };
promo.castling = new Set();
ok(promo.legalMoves(index("a7")).length === 4, "four promotions");
ok(promo.applying(parseMove("a7a8q"))?.piece(index("a8"))?.kind === "q" && promo.notation(parseMove("a7a8q")) === "a8=Q+", "a8=Q+");
ok(promo.applying(parseMove("a7a8")) === null, "a pawn on the last rank must become something");

// the letters: white (my machine) and black (theirs) hold the same letters, each from its own side
const mine = [], theirs = [];
const send = (l, fromWhite) => {
  const text = letterText(l, "Шахматы");
  ok(JSON.stringify(parseLetter(text)) === JSON.stringify(Object.fromEntries(Object.entries(l).filter(([, v]) => v != null))), `the letter ${l.kind} reads back`);
  mine.push({ text, mine: fromWhite }); theirs.push({ text, mine: !fromWhite });
};
const inv = invitation(0, 1_800_000_000_000);
send(inv, true);
let w = games(mine).game, b = games(theirs).game;
ok(w.status === "invited" && w.whiteIsMine && !b.whiteIsMine, "the inviter plays white");
ok(action(w, "accept", { at: inv.at + 1 }) === null, "white cannot accept its own invitation");
send(action(b, "accept", { at: inv.at + 1 }), false);
for (const [word, white] of [["f2f3", true], ["e7e5", false], ["g2g4", true], ["d8h4", false]]) {
  const g = games(white ? mine : theirs).game;
  const l = action(g, "move", { at: g.last.at + 1, move: word });
  ok(!!l, `${word} is allowed`);
  send(l, white);
}
w = games(mine).game; b = games(theirs).game;
ok(w.status === "blackWon" && b.status === "blackWon", "both machines read black's mate");
const end = parseLetter(mine[mine.length - 1].text).end;
ok(end && end.outcome === "won" && end.cause === "mate" && end.moves === 4, "the closing letter names the mate");
ok(games(mine).game.notation.join(" ") === "f3 e5 g4 Qh4#", "the moves in their notation");
// a move out of turn is refused; a step whose parent never came is held
const g2 = replay([{ letter: inv, mine: true }], inv.game);
ok(action(g2, "move", { move: "e2e4" }) === null, "no move before the invitation is accepted");
const stray = { game: inv.game, id: crypto.randomUUID(), parent: crypto.randomUUID(), kind: "move", at: inv.at + 9, move: "e2e4", offerDraw: false };
ok(replay([{ letter: inv, mine: true }, { letter: stray, mine: false }], inv.game).waitingForHistory, "a letter whose parent has not come is held");
ok(parseLetter("♟ Шахматы\nmontana://chess/1/AAAA") === null && parseLetter("привет") === null, "a text that is no game's");
// the engine (iOS MTChessEngine): a legal answer at the weakest level, the mate in one at a strong one
const { reply } = await import("../src/chess-engine.js");
const any = reply(start, 1);
ok(any && start.legalMoves().some((m) => uci(m) === uci(any)), "the weakest level answers with a legal move");
const scholar = play(start, "e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6");
const mateIn1 = reply(scholar, 8);
ok(mateIn1 && uci(mateIn1) === "h5f7", "level 8 finds Qxf7#");
// NO COINS IN A GAME (iOS MTChessWire, the author's word 29.10.2026 19:31 UTC): an invitation names no stake, a move no coin;
// an earlier build's letter that carries them is read without them, and the game replays the same
{
  const ninv = invitation(600, Date.now());
  ok(ninv.stake === undefined && parseLetter(letterText({ ...ninv, stake: 5 }, "Шахматы")).stake === undefined, "an invitation names no stake");
  const old = (l) => "♟ Шахматы\n" + LINK + Buffer.from(JSON.stringify(l)).toString("base64").replace(/\+/g, "-").replace(/\//g, "_");
  const read = parseLetter(old({ ...ninv, stake: 5 }));
  ok(read && read.stake === undefined && read.game === ninv.game, "an earlier build's stake is read without it");
  const book = [{ letter: read, mine: true }];
  const step = (kind, white, extra = {}) => {
    const g = replay(book, ninv.game);
    const l = action(g, kind, { at: g.last.at + 1, mine: white, ...extra });
    if (l) book.push({ letter: parseLetter(old({ ...l, coins: kind === "move" ? 1 : undefined })), mine: white });
    return l;
  };
  step("accept", false);
  for (const [word, white] of [["f2f3", true], ["e7e5", false], ["g2g4", true], ["d8h4", false]]) ok(step("move", white, { move: word }) && !("coins" in book[book.length - 1].letter), `${word} is read without its old coin`);
  ok(book.slice(2).every((e) => e.letter.kind === "move") && action(replay(book.slice(0, 2), ninv.game), "move", { move: "e2e4" }).coins === undefined, "a move names no coin");
  const pg = replay(book, ninv.game);
  ok(pg.status === "blackWon" && !["pooled", "stake", "mintedMine", "mintedTheirs", "accepted"].some((k) => k in pg), "the game counts no pot");
}
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
