// THE ENGINE OFF THE WINDOW'S THREAD (iOS: Task.detached for MTChessEngine.reply): the board stays alive while it thinks.
import { replyFrom } from "./chess-engine.js";

self.onmessage = (e) => {
  const { id, state, level } = e.data;
  self.postMessage({ id, move: replyFrom(state, level) });
};
