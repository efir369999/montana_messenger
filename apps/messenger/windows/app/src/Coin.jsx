import { useEffect, useState } from "react";
import coinFace from "./assets/ios/CoinFace.jpg";
import coinBack from "./assets/ios/CoinBack.jpg";

/** THE COIN IN THE PULL (iOS MontanaCoinSpinner, MontanaChatsList.swift; the author's word 11.09): the numbers of the feel -- the coin
 *  comes in at 40 points of pull, fills in to the trigger at 140, has made its whole round at 240 and never a second; let go past
 *  the trigger, the round it began completes in 0.35 s. */
export const PULL = { side: 58, start: 40, trigger: 140, hold: 82, full: 240, finish: 350 };
export const pullAngle = (p) => 360 * Math.min(1, Math.max(0, (p - PULL.start) / (PULL.full - PULL.start)));
/** The coin itself: in the hand its angle is the pull, let go (`released`: {at, angle}) the round completes at once; the face
 *  through the front half of the turn, the back -- mirrored back again -- through the rear half, a thin white ring (iOS accent). */
export function CoinSpinner({ pull, released }) {
  const [now, setNow] = useState(() => performance.now());
  useEffect(() => {
    if (!released) return undefined;
    let raf = 0;
    const step = () => { setNow(performance.now()); if (performance.now() - released.at < PULL.finish) raf = requestAnimationFrame(step); };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [released]);
  const fraction = Math.min(1, Math.max(0, (pull - PULL.start) / (PULL.trigger - PULL.start)));
  const angle = released ? Math.min(360, released.angle + ((360 - released.angle) * (now - released.at)) / PULL.finish) : pullAngle(pull);
  const a = angle % 360;
  const front = a < 90 || a > 270;
  return (
    <span className="coin-spinner" aria-hidden="true"
          style={{ opacity: released ? 1 : fraction, transform: `scale(${released ? 1 : 0.6 + 0.4 * fraction})` }}>
      <img src={front ? coinFace : coinBack} alt="" draggable={false}
           style={{ transform: `perspective(${PULL.side * 2}px) rotateY(${angle}deg) scaleX(${front ? 1 : -1})` }} />
    </span>
  );
}

/** THE MINT COIN (iOS MTMintCoin, MontanaBoardViews.swift): our coin -- the face and the back of iOS's own pictures (CoinFace,
 *  CoinBack) -- turning about its upright axis in perspective, the back drawn mirrored behind; spinning while it mints (a turn in
 *  1.4 s at speed one, iOS MTCoinDial), standing on its face while it does not; `turn` makes one whole turn (1.1 s, ease in and
 *  out) each time it changes. Reduce Motion stills it. */
export function MintCoin({ side = 22, spinning = false, turn, speed = 1 }) {
  return (
    <span className="mint-coin" aria-hidden="true" style={{ width: side, height: side, perspective: side * 2.5 }}>
      <span className={"mint-coin-body" + (spinning ? " spinning" : "") + (turn !== undefined && !spinning ? " turning" : "")}
            key={turn === undefined ? undefined : `turn-${turn}`} style={spinning ? { animationDuration: `${1.4 / Math.max(1, speed)}s` } : undefined}>
        <img className="mint-coin-face" src={coinFace} alt="" draggable={false} />
        <img className="mint-coin-back" src={coinBack} alt="" draggable={false} />
      </span>
    </span>
  );
}
