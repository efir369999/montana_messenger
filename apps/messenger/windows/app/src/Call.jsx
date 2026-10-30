import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { t } from "./strings.js";
import { Glyph } from "./TopBar.jsx";
import { Face, chatName } from "./Chats.jsx";
import { sendFile } from "./Media.jsx";
import { yieldToCall } from "./player.js";

/** A line of the call's machinery for a check's own diary (Rust writes it only under MONTANA_TRACE). */
const mark = (line) => { invoke("trace", { line: "call " + line }).catch(() => {}); };

/** The road the call's media rides now: the type of the selected pair's local candidate (host, srflx, prflx, relay). */
async function pathKind(pc) {
  try {
    const stats = await pc.getStats();
    let pair = null;
    stats.forEach((r) => { if (r.type === "transport" && r.selectedCandidatePairId) pair = stats.get(r.selectedCandidatePairId); });
    if (!pair) stats.forEach((r) => { if (r.type === "candidate-pair" && r.nominated && r.state === "succeeded") pair = r; });
    const local = pair && stats.get(pair.localCandidateId);
    const pairs = {};
    stats.forEach((r) => {
      if (r.type !== "candidate-pair") return;
      const k = `${stats.get(r.localCandidateId)?.candidateType}-${stats.get(r.remoteCandidateId)?.candidateType}:${r.state}`;
      pairs[k] = (pairs[k] || 0) + 1;
    });
    return (local ? local.candidateType : "none") + " " + JSON.stringify(pairs);
  } catch { return "?"; }
}

/** The pictures a connection carries now, for a check's diary: frames decoded in, frames encoded out. */
async function videoFlow(pc) {
  try {
    const stats = await pc.getStats();
    let got = 0, sent = 0;
    stats.forEach((r) => {
      if (r.type === "inbound-rtp" && r.kind === "video") got += r.framesDecoded || 0;
      if (r.type === "outbound-rtp" && r.kind === "video") sent += r.framesEncoded || 0;
    });
    return `in=${got} out=${sent}`;
  } catch { return "?"; }
}
/** THE FAR VOICE, AS THIS SIDE RECEIVED IT (iOS MTWeave, MTFabricRules.voiced): every few seconds the received audio stream's
 *  counters grew by a stretch -- its seconds, its energy, the samples received and those made up for lost packets; a stretch
 *  counts when its level stands at a voice's floor (-40 dBov) and only by its received share. A call whose far voice stood a
 *  minute or more is a live act of the fabric of time. */
async function weave(pc, w) {
  try {
    const stats = await pc.getStats();
    stats.forEach((r) => {
      if (r.type !== "inbound-rtp" || r.kind !== "audio") return;
      const now = [r.totalSamplesDuration || 0, r.totalAudioEnergy || 0, r.totalSamplesReceived || 0, r.concealedSamples || 0];
      const last = w.seen[r.id] || [0, 0, 0, 0];
      w.seen[r.id] = now;
      const [ds, de, dr, dc] = now.map((v, i) => v - last[i]);
      if (!(ds > 0 && de >= 0 && dr > 0 && dc >= 0) || Math.sqrt(de / ds) < 0.01) return;
      w.heard += ds * Math.min(1, Math.max(0, (dr - dc) / dr));
    });
  } catch { /* a connection let go weighs nothing more */ }
}
/** A picture's size on the screen and the frames under it, written to the diary when they are measured. */
function markPicture(what, video, pc) {
  videoFlow(pc).then((flow) => mark(`${what} ${video ? `${video.videoWidth}x${video.videoHeight}` : "none"} ${flow}`));
}

/** What this side can do, said in every call and answer (iOS caps; Windows' own tier). */
const CAPS = { tier: "windows-webview", ver: 1, opus_max: 40000, hw_aec: true, sframe: false, av: false, rejoin: true };
/** MY RECORDING SWITCH AND MY LEVEL, SAID IN THE CAPS (iOS 2304 CallCaps.rec, lv; MTCallRecording.automatic): the switch as my person
 *  sees it on Access by level (off below its level) and my Global Level -- the far side reads by them whether my switch holds
 *  against it. Read afresh at every call. */
let mine = { rec: false, lv: null };
const readMine = () => invoke("levels_state").then((lv) => { mine = { rec: !!(lv.record?.open && lv.record?.on), lv: Number.isInteger(lv.level) ? lv.level : null }; }).catch(() => {});
const caps = () => ({ ...CAPS, rec: mine.rec, ...(mine.lv === null ? {} : { lv: mine.lv }) });
/** What the far build said of its switch and level, once said standing for the call (iOS learnPeerCaps); unsaid: nothing forbidden. */
const learnCaps = (s, w) => {
  if (typeof w?.rec === "boolean") s.peerRec = w.rec;
  if (Number.isInteger(w?.lv)) s.peerLv = w.lv;
};
/** THE CORRESPONDENT'S SWITCH HOLDS BY LEVEL (iOS MTCallRecordingPolicy.mayRecord, the author's word 20.10.2026 20:2x MSK): their
 *  switch off, only a strictly higher level records; an unknown level holds. A build that says nothing forbids nothing. */
const mayRecord = (theirSwitch, theirLevel, myLevel) => theirSwitch !== false || (theirLevel != null && myLevel != null && myLevel > theirLevel);
/** THE CALL'S COINS ARE ONE FOR BOTH (iOS callRecorded, 20.10.2026 22:0x MSK): recorded by either side by the one rule -- both earn;
 *  by neither -- both burn. */
const callRecorded = (s) => (mine.rec && mayRecord(s.peerRec, s.peerLv, mine.lv)) || (s.peerRec === true && mayRecord(mine.rec, mine.lv, s.peerLv));
const LIFE_MS = 90000;
// THE BREAK IN A CALL (iOS MontanaCall 1190-1205): «disconnected» is the machine's suspicion, «failed» its verdict; a break is
// declared when the suspicion holds; the caller asks for fresh checks at once, the callee after a lead, never over an ask
// still forming; three fresh transports that do not form, or thirty seconds, and the call is honestly lost
const GRACE_MS = 1500, SETTLE_MS = 9000, CALLEE_LEAD_MS = 1500, RESTART_MAX = 3, RECONNECT_MS = 30000;
// THE CALL OUTLIVES ITS PROCESS (iOS HeldCall / rejoinHeldCall / armReconnectDeadline): a peer that rebuilds in place is waited
// for as long as a ring rings -- its run comes back within it; the run that came back waits at least twenty seconds and until
// that window closes; the record is written every five seconds while the call stands; two returns that fell end it
const REJOIN_WINDOW_MS = LIFE_MS, REJOIN_ANSWER_MS = 20000, HOLD_EVERY_MS = 5000, HELD_TRIES = 2;
const reconnectWait = (s) => (s.peerRebuilds ? REJOIN_WINDOW_MS : RECONNECT_MS);
// THE TRANSPORT BUILT ANEW (iOS rebuildInPlace / rebuildForRejoin): once a fresh ask has had its settle and did not form, the
// caller closes the dead connection and offers a new one under the same seed, «call» with the reason «rejoin», every two seconds,
// nine times at most; the peer answers it in place -- nothing rings. A machine that holds no such call and buried its seed says so.
const REJOIN_EVERY_MS = 2000, REJOIN_TIMES = 9;
// THE ROUTE CHANGED (iOS startRouteWatch): the internet's route is read every two seconds while a call stands; a new route asks
// for fresh checks over the relays alone, once in two seconds
const ROUTE_EVERY_MS = 2000;
// A CALL OF TWO GROWS INTO A ROOM (iOS MTCallAddSheet / grow): up to thirteen with me and the peer; the peer's answer is
// waited four seconds (an older build says nothing and the call ends by the rule)
const ROOM_PLACES = 11, ROOM_ANSWER_MS = 4000, ROOM_IN = "in\n";
// A VOICE CALL ASKS FOR PICTURES (iOS toggleVideo / acceptVideoAsk): the ask waits thirty seconds for its answer, and the yes is
// fresh forty -- the asker's re-offer within it brings my camera in, a re-offer minutes later never does
const ASK_MS = 30000, CONSENT_MS = 40000;
// THE SECOND LINE (iOS postSecondLine, the author's word 28.08): another person calling while a call talks rings over it -- its
// own lane, «ringing» back under its own epoch, the waiting pips -- until it is answered, declined or 45 s pass (then a missed
// call); a third caller, a call not yet talking or the same person again is refused with «call-end». «Hold & Accept» parks the
// call in hand (iOS parkCurrent: its connection stays, every track asleep, «call-hold»), «Swap» trades the two lines, and the
// call ended leaves the parked one standing on hold until the person resumes it.
const SECOND_MS = 45000;
// THE CALL RECORDED (iOS MTCallRecording): the person's own key on the call screen; the caller's recording goes to the chat after
// the call, the callee's stays on this computer (only the caller sends a recording, iOS)

/** A connection's name is its certificate (iOS fingerprint): the line «a=fingerprint:» of a description. */
function fingerprint(sdp) {
  const m = /^a=fingerprint:(.*)$/m.exec(sdp || "");
  return m ? m[1].trim().toLowerCase() : null;
}

/** A fresh call seed (iOS: 32 random bytes in base64, 44 characters); its first sixteen are the call's epoch. */
function newSeed() {
  const b = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...b));
}

/** Opus as iOS tunes it (MontanaCall 2309-2313): mono, the given average rate, full playback, variable. */
function tune(sdp, rate) {
  return sdp.replace(/useinbandfec=1/g, `useinbandfec=1;stereo=0;maxaveragebitrate=${rate};maxplaybackrate=48000;cbr=0`);
}

/** The TURN pass as an RTCConfiguration (iOS MontanaCall 1688-1770): the STUN first, then the TURN roads, TLS on 443 first. */
function config(pass) {
  const servers = [];
  if (pass?.stun?.length) servers.push({ urls: pass.stun });
  if (pass?.uris?.length) {
    const rank = (u) => (u.startsWith("turns:") && u.includes(":443") ? 0 : u.startsWith("turns:") ? 1 : u.includes("transport=tcp") ? 2 : 3);
    servers.push({ urls: [...pass.uris].sort((a, b) => rank(a) - rank(b)), username: pass.username, credential: pass.credential });
  }
  return { iceServers: servers, bundlePolicy: "max-bundle", iceTransportPolicy: "all" };
}

/** THE CALL (iOS MontanaCall): one at a time; the window rings, talks and ends it; Rust carries its words. */
// THE FOLDED CALL, TOLD TO THE ROWS (iOS CallUIModel.foldedLive and its peer, CallInlineHandset): the row of the person the folded
// call is with wears the handsets -- the green to return to it, the red to end it -- and the layer's own deeds answer them
let foldedNow = null;
const foldedEars = new Set();
let callDeeds = null;
function tellFolded(v) {
  if ((foldedNow?.chat ?? null) === (v?.chat ?? null) && (foldedNow?.video ?? null) === (v?.video ?? null)) return;
  foldedNow = v;
  foldedEars.forEach((f) => f(v));
}
/** The call folded into the app, or null: {chat, video}. */
export function useFoldedCall() {
  const [v, setV] = useState(foldedNow);
  useEffect(() => { foldedEars.add(setV); setV(foldedNow); return () => { foldedEars.delete(setV); }; }, []);
  return v;
}
/** The folded call comes back (the green handset) or ends (the red, once asked). */
export const unfoldCall = () => callDeeds?.unfold();
export const endFoldedCall = () => callDeeds?.end();

export default function CallLayer({ person, pillHidden = false }) {
  const [call, setCall] = useState(null);   // {phase: out|in|talk|end, chat, name, seed, epoch, video, incoming, status, at}
  const [muted, setMuted] = useState(false);
  const [cameras, setCameras] = useState(0);   // the cameras of this computer, asked when a video call stands
  const [held, setHeld] = useState(false);       // I hold the call: the tracks sleep both ways
  const [asking, setAsking] = useState(false);   // my ask for pictures waits its answer
  const [asked, setAsked] = useState(false);     // the peer asks for pictures
  const [taping, setTaping] = useState(false);   // this side records the call
  const [adding, setAdding] = useState(null);   // whom to add: the people, the chosen
  const [sharing, setSharing] = useState(false); // my screen rides the video lane
  const [second, setSecond] = useState(null);    // the second line ringing over the call: {chat, name, seed, epoch, video, offer, at}
  const [parked, setParked] = useState(null);    // the call parked aside: {name, chat, heldByPeer}
  const secondRef = useRef(null), parkedRef = useRef(null), tone = useRef({}), gone = useRef(new Set()), answering = useRef(null);
  const [now, setNow] = useState(Date.now());
  // THE CALL FOLDS INTO THE APP (iOS CallUIModel.fold): the back mark, a stroke down or Esc folds it -- the voice goes on -- and the
  // pill at the window's foot brings it back or ends it
  const [folded, setFolded] = useState(false);
  const fold = (v, why) => { setFolded(v); mark(`fold ${v ? "folded" : "unfolded"} by=${why}`); };
  useEffect(() => {
    tellFolded(call && folded && call.phase !== "in" && call.phase !== "end" ? { chat: call.chat, video: !!call.video } : null);
  }, [call, folded]);
  const stroke = useRef(null);
  // a call that ended leaves nothing folded behind; Esc folds the call standing open (iOS: the back mark's road)
  useEffect(() => { if (!call) setFolded(false); }, [call]);
  useEffect(() => {
    const key = (e) => {
      if (e.key !== "Escape" || !call || folded || call.phase === "in" || call.phase === "end") return;
      e.stopPropagation(); setFolded(true); mark("fold folded by=esc");
    };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  }, [call, folded]);
  const st = useRef({});                     // the engine: pc, stream, offer, ice buffers, timers, words heard
  const remoteVideo = useRef(null), localVideo = useRef(null), remoteAudio = useRef(null);
  const live = useRef(null);
  live.current = call;
  window.montanaCallBusy = () => !!live.current && live.current.phase !== "end";   // a group's room asks before it opens

  const post = (c, words) => invoke("call_post", { chat: c.chat, epoch: c.epoch, words: JSON.stringify(words) });
  const word = (c, ctrl, extra = {}) => ({ t: "cal", ctrl, ts: Date.now(), e: c.epoch, ...extra });

  const finish = async (reason, tell) => {
    const c = live.current;
    if (!c || c.phase === "end") return;
    const s = st.current;
    const talked = c.phase === "talk" && s.connectedAt ? Math.floor((Date.now() - s.connectedAt) / 1000) : 0;
    const recorded = !!s.tape || callRecorded(s);
    if (tell) await post(c, [word(c, "call-end")]);
    if (s.tape) stopTape(s, c);   // the call's end ends its recording, and the recording goes where it goes
    clearTimeout(s.timer); clearInterval(s.iceTimer); clearTimeout(s.grace); clearInterval(s.restartTimer); clearTimeout(s.deadline);
    clearInterval(s.routeTimer); clearTimeout(s.rejoinTimer); clearInterval(s.holdTimer); clearTimeout(s.askTimer);
    clearInterval(s.weaveTimer);
    if (s.weave && s.pc) await weave(s.pc, s.weave);   // the last stretch before the connection goes
    s.pc?.close(); s.stream?.getTracks().forEach((x) => x.stop());
    if (s.share) { s.share.onended = null; s.share.stop(); }
    setSharing(false);
    const secs = s.connectedAt ? Math.round((Date.now() - s.connectedAt) / 1000) : 0;
    const missed = !s.connectedAt && !(c.incoming && s.answered);
    // the call's last whole second settles before the clock is cleared, and the end lays its burn at once (iOS MTCallMint.finish)
    const settled = talked > 0 ? invoke("call_coins", { call: c.epoch, seconds: talked, recording: recorded }).catch(() => {}) : Promise.resolve();
    settled.then(() => invoke("call_end", { chat: c.chat, seed: c.seed, video: !!c.video || !!s.hadVideo, incoming: !!c.incoming, seconds: secs,
                                            missed, heard: Math.floor(s.weave?.heard || 0) }));
    st.current = {};
    setCall({ ...c, phase: "end", status: reason === "no-path" ? t("The call found no way") : t("Call ended") });
    setTimeout(() => setCall((x) => (x?.phase === "end" ? null : x)), 1800);
    // ANOTHER LINE STANDS (iOS): the parked call comes back to the screen still on hold, until the person resumes it; a second
    // line still ringing rings on as the call itself
    const pk = parkedRef.current, s2 = secondRef.current;
    if (pk) {
      parkedRef.current = null; setParked(null);
      bringBack(pk);
    } else if (s2) {
      secondRef.current = null; setSecond(null); waitingTone(false); clearTimeout(s2.timer);
      const c2 = { phase: "in", chat: s2.chat, name: s2.name, seed: s2.seed, epoch: s2.epoch, video: s2.video, incoming: true, status: "", at: s2.at };
      st.current = { seen: new Set(), offer: s2.offer };
      live.current = c2;
      setCall(c2); setMuted(false); setHeld(false); setAsking(false); setAsked(false);
      st.current.timer = setTimeout(() => { if (!st.current.answered) finish("timeout", false); }, Math.max(5000, SECOND_MS - (Date.now() - s2.at)));
      mark("second line rings on as the call");
    }
  };

  /** THE WAITING PIPS (iOS startWaitingTone): two short tones every three seconds while a second line rings over a call. */
  const waitingTone = (on) => {
    const w = tone.current;
    clearInterval(w.timer); w.timer = null;
    if (!on) return;
    const pip = () => {
      try {
        const ctx = w.ctx || (w.ctx = new AudioContext());
        for (const at of [0, 0.3]) {
          const o = ctx.createOscillator(), g = ctx.createGain();
          o.frequency.value = 440; g.gain.value = 0.06;
          o.connect(g).connect(ctx.destination);
          o.start(ctx.currentTime + at); o.stop(ctx.currentTime + at + 0.15);
        }
      } catch { /* no sound to make: the banner still stands */ }
    };
    pip();
    w.timer = setInterval(pip, 3000);
  };

  /** A SECOND CALL RINGS (iOS postSecondLine): over a call that talks, with its own lane and «ringing» under its own epoch. */
  const secondRing = async (chat, seed, video, name, offer) => {
    const c = live.current, s2 = secondRef.current, pk = parkedRef.current;
    if (s2 && s2.seed === seed) { if (offer && !s2.offer) s2.offer = offer; return; }
    if (pk && pk.c.seed === seed) return;   // the parked call's own word
    // the line being answered is no second ring: its caller's repeated word lands while the call in hand is parked
    if (answering.current?.seed === seed) { if (offer && !answering.current.offer) answering.current.offer = offer; return; }
    if (gone.current.has(seed) || await invoke("call_buried", { seed })) return;   // a line declined a moment ago rings no more
    const epoch = seed.slice(0, 16);
    if (s2 || pk || c.phase !== "talk" || c.chat === chat) {
      mark(`second line refused third=${!!(s2 || pk)} phase=${c.phase} same=${c.chat === chat}`);
      post({ chat, epoch }, [word({ epoch }, "call-end")]);
      return;
    }
    const ring = { chat, name, seed, epoch, video: video || /m=video/.test(offer?.sdp || ""), offer, at: Date.now() };
    secondRef.current = ring; setSecond(ring);
    await invoke("call_begin", { chat, seed, video: ring.video, outgoing: false });
    await post(ring, [word(ring, "call-ringing")]);
    mark(`second line rings video=${ring.video}`);
    waitingTone(true);
    ring.timer = setTimeout(() => { if (secondRef.current === ring) dropSecond("expired"); }, SECOND_MS);
  };
  /** The second line goes: declined (its caller told), expired (a missed call), or ended by its caller. */
  const dropSecond = async (how) => {
    const ring = secondRef.current;
    if (!ring) return;
    secondRef.current = null; setSecond(null);
    clearTimeout(ring.timer); waitingTone(false);
    if (how === "declined") await post(ring, [word(ring, "call-end")]);
    const end = () => invoke("call_end", { chat: ring.chat, seed: ring.seed, video: !!ring.video, incoming: true, seconds: 0, missed: how === "expired", row: how === "expired" });
    // A DECLINE IS HEARD (the caller's word rides the lane with its receipt): the line's run lives a few seconds more, so the «call-end»
    // goes again until the caller's receipt; the line's late words ring nothing meanwhile
    gone.current.add(ring.seed);
    if (how === "declined") setTimeout(end, 8000); else end();
    mark(`second line ${how}`);
  };
  /** «Завершить и принять» or «Удержать и принять» (iOS answerSecond): the call in hand ends, or is parked; the second becomes the call. */
  const answerSecond = async (hold) => {
    const ring = secondRef.current;
    if (!ring) return;
    secondRef.current = null; setSecond(null);
    answering.current = ring;
    clearTimeout(ring.timer); waitingTone(false);
    if (!(hold && await park())) await finish("swapped-to-second", true);
    const c = { phase: "in", chat: ring.chat, name: ring.name, seed: ring.seed, epoch: ring.epoch, video: ring.video, incoming: true, status: "", at: ring.at };
    st.current = { seen: new Set(), offer: ring.offer };
    live.current = c;
    answering.current = null;
    setCall(c); setMuted(false); setHeld(false); setAsking(false); setAsked(false);
    mark(`second line answered hold=${hold}`);
    await accept();
  };
  /** PARK THE CALL IN HAND (iOS parkCurrent): its connection stays with every track asleep, the peer hears «call-hold», and the
   *  machine is free for the other line; a recording or a share of it ends first. */
  const park = async () => {
    const c = live.current, s = st.current;
    if (!c || c.phase !== "talk" || !s.connectedAt || s.reconnecting || !s.pc) return false;
    if (s.tape) stopTape(s, c);
    if (s.share) await stopShare();
    s.stream?.getTracks().forEach((x) => (x.enabled = false));
    s.pc.getReceivers().forEach((r) => { if (r.track) r.track.enabled = false; });
    s.held = true;
    clearInterval(s.routeTimer); s.routeTimer = null;
    clearTimeout(s.grace);
    await post(c, [word(c, "call-hold")]);
    parkedRef.current = { c, s };
    setParked({ name: c.name, chat: c.chat, heldByPeer: !!c.heldByPeer });
    mark("call parked");
    return true;
  };
  /** A parked call takes the machine again (iOS unpark): its tracks wake as the person left them, the peer hears «call-resume». */
  const unpark = async ({ c, s }) => {
    st.current = s; live.current = c;
    s.held = false;
    s.stream?.getAudioTracks().forEach((x) => (x.enabled = !s.muted));
    s.stream?.getVideoTracks().forEach((x) => (x.enabled = true));
    s.pc?.getReceivers().forEach((r) => { if (r.track) r.track.enabled = true; });
    if (!s.routeTimer) s.routeTimer = setInterval(watchRoute, ROUTE_EVERY_MS);
    setCall({ ...c, phase: "talk" }); setMuted(!!s.muted); setHeld(false); setAsking(false); setAsked(false);
    await post(c, [word(c, "call-resume")]);
    mark("call resumed from the park");
  };
  /** «Переключить» (iOS swapWithParked): the call in hand parks, the parked one comes back; no park -- no swap. */
  const swap = async () => {
    const other = parkedRef.current;
    if (!other) return;
    parkedRef.current = null;
    if (!(await park())) { parkedRef.current = other; mark("swap refused"); return; }
    await unpark(other);
    mark("swapped");
  };
  /** The call in hand ended and a parked one stands: it comes to the screen still asleep, «Удержать» lit -- the person resumes it. */
  const bringBack = ({ c, s }) => {
    st.current = s; live.current = { ...c, phase: "talk" };
    s.held = true;
    if (!s.routeTimer) s.routeTimer = setInterval(watchRoute, ROUTE_EVERY_MS);
    setCall(live.current); setMuted(!!s.muted); setHeld(true); setAsking(false); setAsked(false);
    mark("the parked call stands again, on hold");
  };
  /** The parked call's own words: its end, the peer's hold, its candidates (iOS: call-end of the parked peer tears it). */
  const hearParked = async (w) => {
    const pk = parkedRef.current;
    if (w.ctrl === "call-end" || w.ctrl === "call-gone") {
      parkedRef.current = null; setParked(null);
      const s = pk.s;
      clearInterval(s.iceTimer); clearInterval(s.holdTimer); clearInterval(s.restartTimer); clearTimeout(s.deadline); clearTimeout(s.grace);
      s.pc?.close(); s.stream?.getTracks().forEach((x) => x.stop());
      invoke("call_end", { chat: pk.c.chat, seed: pk.c.seed, video: !!pk.c.video || !!s.hadVideo, incoming: !!pk.c.incoming,
                           seconds: s.connectedAt ? Math.round((Date.now() - s.connectedAt) / 1000) : 0, missed: false });
      mark("the parked call's peer hung up");
    } else if (w.ctrl === "call-hold" || w.ctrl === "call-resume") {
      pk.c = { ...pk.c, heldByPeer: w.ctrl === "call-hold" };
      setParked((x) => (x ? { ...x, heldByPeer: w.ctrl === "call-hold" } : x));
    } else if (w.ctrl === "call-ice") {
      for (const cand of w.candidate ? [w.candidate] : w.candidates || []) await pk.s.pc?.addIceCandidate(cand).catch(() => {});
    }
  };

  /** The peer connection with its candidates: held by the caller until the far side rings (or 8 s), then sent in batches. */
  const connect = async (c, reuse = false) => {
    const s = st.current;
    const pass = await invoke("turn_cred").catch(() => null);
    const cfg = config(pass);
    if (s.relayOnly) cfg.iceTransportPolicy = "relay";
    const pc = new RTCPeerConnection(cfg);
    clearInterval(s.iceTimer);
    s.pc = pc; s.ice = []; s.remoteIce = s.remoteIce || [];   // candidates heard while the connection was built wait for it
    if (!s.routeTimer) s.routeTimer = setInterval(watchRoute, ROUTE_EVERY_MS);
    pc.onicecandidate = (e) => {
      if (!e.candidate || st.current.pc !== pc) return;
      if (s.relayOnly) mark(`ice local type=${e.candidate.type}`);
      s.ice.push({ candidate: e.candidate.candidate, sdpMid: e.candidate.sdpMid, sdpMLineIndex: e.candidate.sdpMLineIndex });
    };
    s.iceTimer = setInterval(() => {
      const hold = !c.incoming && !s.heard && Date.now() - c.at < 8000;
      if (hold || !s.ice.length) return;
      const batch = s.ice.splice(0);
      post(c, batch.map((candidate) => word(c, "call-ice", { candidate })));
    }, 200);
    pc.ontrack = (e) => {
      if (st.current.pc !== pc) return;
      const stream = e.streams[0] || new MediaStream([e.track]);
      // the picture is kept even while no video stands on the screen: a peer's share grows one later (iOS remoteVideoTrack)
      if (e.track.kind === "video") s.remoteVideo = stream; else s.remoteAudio = stream;
      if (remoteAudio.current && e.track.kind === "audio") remoteAudio.current.srcObject = stream;
      if (remoteVideo.current && e.track.kind === "video") remoteVideo.current.srcObject = stream;
    };
    pc.onconnectionstatechange = () => {
      if (st.current.pc !== pc) return;   // a connection let go speaks no more
      const state = pc.connectionState;
      mark(`state=${state} reconnecting=${!!s.reconnecting} rejoining=${!!s.rejoining}`);
      if (state === "connected") {
        if (!s.holdTimer) { s.holdTimer = setInterval(() => keepOnDisk(s), HOLD_EVERY_MS); }
        s.rejoins = 0;   // a return that stood is no fall
        if (!s.connectedAt) {
          s.connectedAt = Date.now();
          s.weave = { heard: 0, seen: {} };
          s.weaveTimer = setInterval(() => weave(pc, s.weave), 5000);
          // CALLS RECORD THEMSELVES FROM LEVEL 7 (iOS MTLevelAccess.autoRecord, after the person's first consent): below it the
          // record button alone records
          invoke("levels_state").then((lv) => {
            if (lv.record.open && lv.record.on && lv.record.consent && st.current === s && !s.tape) { mark("record auto level"); startTape(); }
          }).catch(() => {});
          invoke("call_heard", { talking: true, seed: c.seed });
          setCall((x) => (x ? { ...x, phase: "talk" } : x));
          if (c.video) for (const ms of [4000, 9000]) setTimeout(() => markPicture("picture seen", remoteVideo.current, pc), ms);
        }
        if (s.reconnecting) leaveReconnecting();
        s.rejoining = false; clearTimeout(s.rejoinTimer);
        clearTimeout(s.grace);
      }
      if (state === "disconnected" && s.connectedAt && !s.reconnecting) {
        clearTimeout(s.grace);
        s.grace = setTimeout(() => { if (pc.connectionState !== "connected") enterReconnecting(); }, GRACE_MS);
      }
      if (state === "failed") {
        if (!s.connectedAt) finish("no-path", true);
        else if (!s.reconnecting) enterReconnecting();
        else requestRestart();   // the verdict: an ask goes even over one forming
      }
    };
    const audio = { echoCancellation: true, noiseSuppression: true };
    let stream = reuse ? s.stream : null;
    if (stream) {
      // the same voice and picture on the new connection -- the screen in the camera's place while it rides
      stream.getTracks().forEach((track) => pc.addTrack(track.kind === "video" && s.share ? s.share : track, stream));
      if (s.share && !stream.getVideoTracks().length) pc.addTrack(s.share, stream);
      return pc;
    }
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio, video: c.video ? { width: 1280, height: 720, frameRate: 24 } : false });
    } catch (e) {
      if (!c.video) throw e;
      // the camera would not open (iOS: «Камера выключена для Montana» -- «Продолжить голосом»): the call goes on by voice
      stream = await navigator.mediaDevices.getUserMedia({ audio });
      c.video = false;
      setCall((x) => (x ? { ...x, video: false } : x));
    }
    s.stream = stream;
    if (stream.getVideoTracks().length) s.hadVideo = true;
    stream.getTracks().forEach((track) => pc.addTrack(track, stream));
    if (localVideo.current && c.video) localVideo.current.srcObject = stream;
    return pc;
  };

  /** THE BREAK (iOS enterReconnecting): «Восстановление связи…», fresh checks asked, a deadline for the verdict. */
  const enterReconnecting = () => {
    const s = st.current;
    if (!s.pc || s.reconnecting) return;
    mark(`reconnecting peerRebuilds=${!!s.peerRebuilds}`);
    s.reconnecting = true; s.restarts = 0;
    setCall((x) => (x ? { ...x, status: t("Reconnecting…"), reconnecting: true } : x));
    requestRestart();
    s.restartTimer = setInterval(() => {
      const c = live.current;
      // A FRESH TRANSPORT AFTER ONE ASK THAT DID NOT FORM (iOS scheduleIceRestart): the caller rebuilds in place, by the rejoin
      // road, once the peer said it answers one; the callee keeps its asks and answers the rebuild
      if (c && !c.incoming && s.peerRebuilds && s.restarts >= 1 && !s.rebuilt && Date.now() - (s.restartAskedAt || 0) >= SETTLE_MS) {
        clearInterval(s.restartTimer);
        rebuildInPlace();
        return;
      }
      if (!st.current.reconnecting || st.current.restarts >= RESTART_MAX) { clearInterval(s.restartTimer); return; }
      requestRestart();
    }, 3000);
    s.deadline = setTimeout(() => { if (st.current.reconnecting) finish("lost", true); }, reconnectWait(s));
  };
  const leaveReconnecting = () => {
    const s = st.current;
    s.reconnecting = false;
    clearInterval(s.restartTimer); clearTimeout(s.deadline);
    setCall((x) => (x ? { ...x, reconnecting: false } : x));
  };
  /** The one owner of «ask for fresh checks» (iOS requestIceRestart): the caller at once, the callee after the lead. */
  const requestRestart = (force = false) => {
    const s = st.current, c = live.current;
    if (!s.pc || !c || c.phase === "end") return;
    if (Date.now() - (s.restartAskedAt || 0) < SETTLE_MS && s.pc.iceConnectionState !== "failed") return;
    const asked = s.restartAskedAt = Date.now();
    mark(`restart asked force=${force}`);
    setTimeout(() => {
      const now = st.current;
      if (now !== s || (!force && !s.reconnecting) || s.restartAskedAt !== asked) return;
      if (s.reconnecting) s.restarts = (s.restarts || 0) + 1;
      offerAgain(true);
    }, c.incoming ? CALLEE_LEAD_MS : 0);
  };

  /** THE ROUTE WATCH (iOS startRouteWatch): a route that changed under a standing call asks for checks over the relays. */
  const watchRoute = async () => {
    const s = st.current;
    if (!s.pc) return;
    const k = await invoke("route_key").catch(() => "");
    if (!k || st.current !== s) return;   // only a standing route names one
    if (!s.routeKey) { s.routeKey = k; return; }
    if (k === s.routeKey) return;
    s.routeKey = k;
    if (!s.connectedAt || Date.now() - (s.routeAt || 0) < 2000) return;
    s.routeAt = Date.now();
    routeRelayRecovery();
  };
  /** A crossing of networks (iOS requestRouteRelayRecovery): the pass kept, the checks bound to its relays, one fresh ask. */
  const routeRelayRecovery = async () => {
    const s = st.current, pc = s.pc;
    if (!pc) return;
    const pass = await invoke("turn_cred").catch(() => null);
    if (st.current !== s || s.pc !== pc) return;
    const cfg = config(pass);
    cfg.iceTransportPolicy = "relay";
    try { pc.setConfiguration(cfg); } catch { /* the machine keeps its configuration; the ask still goes */ }
    s.relayOnly = true;
    s.restartAskedAt = 0;
    mark("route changed: the checks go over the relays alone");
    requestRestart(true);
    for (const ms of [8000, 16000]) {
      setTimeout(async () => { if (st.current === s && s.pc === pc) mark(`route recovery path=${await pathKind(pc)} after ${ms / 1000}s ice=${pc.iceConnectionState}`); }, ms);
    }
  };

  /** THE LIVING CALL REBUILDS ITS OWN TRANSPORT (iOS rebuildInPlace): the dead connection closed, a new one offered by the
   *  rejoin road; the call keeps its clock and its screen. */
  const rebuildInPlace = async () => {
    const s = st.current, c = live.current;
    if (!s.pc || !c || c.phase === "end" || s.rebuilt) return;
    s.rebuilt = true; s.rejoining = true;
    mark(`rebuild in place restarts=${s.restarts}`);
    clearInterval(s.restartTimer);
    const dead = s.pc;
    s.pc = null; dead.close();
    s.seenRestartOffer = ""; s.seenRestartAnswer = "";
    try {
      const pc = await connect(c, true);
      const offer = await pc.createOffer();
      const sdp = tune(offer.sdp, 64000);
      await pc.setLocalDescription({ type: "offer", sdp });
      s.rejoinSdp = sdp;
      sendRejoinOffer(pc, sdp, 0);
    } catch { /* the deadline speaks */ }
  };
  const sendRejoinOffer = (pc, sdp, n) => {
    const s = st.current, c = live.current;
    if (!c || st.current.pc !== pc || pc.remoteDescription || n >= REJOIN_TIMES) return;
    mark(`rejoin offer n=${n + 1}`);
    post(c, [word(c, "call", { n: person.name, s: c.seed, caps: caps(), video: !!c.video, sdp: { type: "offer", sdp }, reason: "rejoin" })]);
    s.rejoinTimer = setTimeout(() => sendRejoinOffer(pc, sdp, n + 1), REJOIN_EVERY_MS);
  };
  /** THE PEER BUILT ITS TRANSPORT ANEW (iOS rebuildForRejoin): the dead connection here closed, the new offer answered in place;
   *  an offer under this connection's own certificate is a copy, never a rebirth. */
  const rebuildForRejoin = async (w) => {
    const s = st.current, c = live.current;
    if (!c || s.seenRejoin === w.sdp.sdp) return;
    const theirs = s.pc?.remoteDescription ? fingerprint(s.pc.remoteDescription.sdp) : null;
    if (theirs && theirs === fingerprint(w.sdp.sdp)) return;
    s.seenRejoin = w.sdp.sdp;
    mark("rejoin heard: the dead connection here is closed, the new offer answered");
    s.peerRebuilds = !!w.caps?.rejoin;
    learnCaps(s, w.caps);
    clearInterval(s.restartTimer); clearTimeout(s.rejoinTimer); s.rejoining = false;
    s.seenRestartOffer = ""; s.seenRestartAnswer = "";
    if (s.connectedAt && !s.reconnecting) {
      s.reconnecting = true;
      setCall((x) => (x ? { ...x, status: t("Reconnecting…"), reconnecting: true } : x));
      clearTimeout(s.deadline);
      s.deadline = setTimeout(() => { if (st.current.reconnecting) finish("lost", true); }, reconnectWait(s));
    }
    const dead = s.pc;
    s.pc = null; dead?.close();
    try {
      const pc = await connect(c, true);
      await pc.setRemoteDescription({ type: "offer", sdp: w.sdp.sdp });
      notePeer(w.sdp.sdp);
      await drainIce();
      const answer = await pc.createAnswer();
      const sdp = tune(answer.sdp, c.incoming ? 40000 : 64000);
      await pc.setLocalDescription({ type: "answer", sdp });
      await post(c, [word(c, "call-answer", { sdp: { type: "answer", sdp }, caps: caps() })]);
      mark("rejoin answered");
    } catch (e) { mark(`rejoin answer refused ${e?.message || e}`); }
  };
  /** A mid-call re-offer (iOS sendRenegotiationOffer): fresh ICE, said as «call-restart» with the reason «ice». */
  const offerAgain = async (ice) => {
    const s = st.current, c = live.current, pc = s.pc;
    if (!pc || !c) return;
    try {
      const offer = await pc.createOffer({ iceRestart: ice });
      const sdp = tune(offer.sdp, c.incoming ? 40000 : 64000);
      await pc.setLocalDescription({ type: "offer", sdp });
      await post(c, [word(c, "call-restart", { sdp: { type: "offer", sdp }, caps: caps(), reason: ice ? "ice" : "media" })]);
    } catch { /* the machine refused this round; the next ask comes with the timer */ }
  };
  /** Their re-offer (iOS «call-restart»): of this very connection only; the callee yields in a glare; answered at once. */
  const restartHeard = async (w) => {
    const s = st.current, c = live.current, pc = s.pc;
    if (!pc || !w.sdp?.sdp || !pc.remoteDescription) return;
    if (fingerprint(pc.remoteDescription.sdp) !== fingerprint(w.sdp.sdp)) return;   // a restart word of another connection
    if (s.seenRestartOffer === w.sdp.sdp) return;
    s.seenRestartOffer = w.sdp.sdp;
    try {
      if (pc.signalingState === "have-local-offer") {
        if (!c.incoming) return;   // the caller keeps its own offer; the callee yields
        await pc.setLocalDescription({ type: "rollback" });
      }
      await pc.setRemoteDescription({ type: "offer", sdp: w.sdp.sdp });
      const answer = await pc.createAnswer();
      const sdp = tune(answer.sdp, c.incoming ? 40000 : 64000);
      await pc.setLocalDescription({ type: "answer", sdp });
      await post(c, [word(c, "call-restart-answer", { sdp: { type: "answer", sdp } })]);
      // THE YES JOINS HERE (iOS K-6): only while fresh and only on a «media» offer -- fresh checks minutes later raise no camera
      if (w.reason !== "ice" && s.consentAt && Date.now() - s.consentAt < CONSENT_MS) { s.consentAt = 0; cameraIn("joined by invitation"); }
    } catch { /* refused: the asker asks again */ }
  };
  const restartAnswered = async (w) => {
    const s = st.current, pc = s.pc;
    if (!pc || !w.sdp?.sdp || !pc.remoteDescription || fingerprint(pc.remoteDescription.sdp) !== fingerprint(w.sdp.sdp)) return;
    if (s.seenRestartAnswer === w.sdp.sdp || pc.signalingState !== "have-local-offer") return;
    s.seenRestartAnswer = w.sdp.sdp;
    await pc.setRemoteDescription({ type: "answer", sdp: w.sdp.sdp }).catch(() => {});
  };

  /** The peer's connections this call has known, by their certificates: a run that comes back buries their late words. */
  const notePeer = (sdp) => {
    const s = st.current, f = fingerprint(sdp);
    if (!f) return;
    s.peerFPs = s.peerFPs || [];
    if (!s.peerFPs.includes(f)) s.peerFPs.push(f);
  };
  const deadWord = (w) => !!w.sdp?.sdp && !!st.current.deadFPs?.has(fingerprint(w.sdp.sdp));

  const addIce = async (cand) => {
    const s = st.current;
    if (!s.pc?.remoteDescription) { s.remoteIce = s.remoteIce || []; if (s.remoteIce.length < 64) s.remoteIce.push(cand); return; }
    await s.pc.addIceCandidate(cand).catch(() => {});
  };
  const drainIce = async () => { const s = st.current; for (const x of (s.remoteIce || []).splice(0)) await s.pc.addIceCandidate(x).catch(() => {}); };

  /** A CALL OF MINE (iOS startCall): the bare invitation first, then the offer; the knocks and the ring letter go from Rust. */
  const start = async (chat, name, video) => {
    if (live.current) return;
    if (window.montanaRoomBusy?.()) { window.dispatchEvent(new CustomEvent("montana-room-say", { detail: "Leave the group call first" })); return; }
    yieldToCall();   // a call takes the sound: what plays stands down (iOS VoicePlayer.yieldToCall)
    const seed = newSeed();
    const c = { phase: "out", chat, name, seed, epoch: seed.slice(0, 16), video, incoming: false, status: t("Connecting…"), at: Date.now() };
    st.current = { seen: new Set() };
    setCall(c); setMuted(false); setHeld(false); setAsking(false); setAsked(false);
    await readMine();
    await invoke("call_begin", { chat, seed, video, outgoing: true });
    const me = { n: person.name, s: seed, caps: caps(), video };
    await post(c, [word(c, "call", me)]);
    setCall((x) => (x ? { ...x, status: t("Calling…") } : x));
    try {
      const pc = await connect(c);
      const offer = await pc.createOffer();
      const sdp = tune(offer.sdp, 64000);
      await pc.setLocalDescription({ type: "offer", sdp });
      await post(c, [word(c, "call", { ...me, sdp: { type: "offer", sdp } })]);
    } catch {
      return finish("media", true);
    }
    st.current.timer = setTimeout(() => { if (!st.current.connectedAt) finish("timeout", true); }, LIFE_MS);
  };

  /** A CALL THAT RINGS HERE (iOS: a birth): «ringing» back, the offer kept until the person answers. */
  const ringing = async (chat, seed, video, name, offer, caps) => {
    if (live.current && live.current.seed !== seed && live.current.phase !== "end") return secondRing(chat, seed, video, name, offer);
    if (live.current) {
      if (live.current.seed === seed && offer && !st.current.offer) st.current.offer = offer;
      // a call rung first by its letter learns from its own word that the caller rebuilds in place
      if (live.current.seed === seed && caps?.rejoin) st.current.peerRebuilds = true;
      if (live.current.seed === seed) learnCaps(st.current, caps);
      if (live.current.seed === seed) post(live.current, [word(live.current, "call-ringing")]);
      return;
    }
    if (await invoke("call_buried", { seed })) return;
    const c = { phase: "in", chat, name, seed, epoch: seed.slice(0, 16), video: video || /m=video/.test(offer?.sdp || ""), incoming: true,
                status: "", at: Date.now() };
    st.current = { seen: new Set(), offer, peerRebuilds: !!caps?.rejoin };
    learnCaps(st.current, caps);
    readMine();
    setCall(c); setMuted(false); setHeld(false); setAsking(false); setAsked(false);
    await invoke("call_begin", { chat, seed, video: c.video, outgoing: false });
    await post(c, [word(c, "call-ringing")]);
    st.current.timer = setTimeout(() => { if (!st.current.answered) finish("timeout", false); }, LIFE_MS);
  };

  const accept = async () => {
    const c = live.current, s = st.current;
    s.answered = true;
    yieldToCall();
    setCall({ ...c, phase: "talk", status: t("Connecting…") });
    for (let i = 0; i < 30 && !s.offer; i++) await new Promise((r) => setTimeout(r, 500));
    if (!s.offer) return finish("offer-missing", true);
    try {
      const pc = await connect(c);
      await pc.setRemoteDescription(s.offer);
      notePeer(s.offer.sdp);
      await drainIce();
      const answer = await pc.createAnswer();
      const sdp = tune(answer.sdp, 40000);
      await pc.setLocalDescription({ type: "answer", sdp });
      await post(c, [word(c, "call-answer", { sdp: { type: "answer", sdp }, caps: caps() })]);
      s.heard = true;
    } catch {
      finish("answer-refused-here", true);
    }
  };

  /** THE CALL'S WORDS (iOS handleCallSignal): each array once; the end first. */
  const hear = async (chat, epoch, text) => {
    let words;
    try { words = JSON.parse(text); } catch { return; }
    if (!Array.isArray(words)) return;
    words.sort((a, b) => (a.ctrl === "call-end" ? -1 : b.ctrl === "call-end" ? 1 : 0));
    for (const w of words) {
      if (w?.t !== "cal" || w.e !== epoch) continue;
      const c = live.current, s = st.current;
      if (w.ctrl !== "call-ice") mark(`heard ${w.ctrl}${w.reason ? " " + w.reason : ""}`);
      if (w.ctrl === "call") {
        if (!w.s || w.s.slice(0, 16) !== epoch) continue;
        if (w.reason === "rejoin") {
          // A REJOIN IS NEVER A BIRTH (iOS handleSignalBody): of the call held here it rebuilds the connection in place; both
          // rebuilt at once, the caller's offer stands; of a call that ended here, the far side is told it ended
          if (c && c.seed === w.s && c.chat === chat && c.phase !== "end" && w.sdp?.type === "offer") {
            if (w.sdp.sdp === s.rejoinSdp) continue;   // my own rejoin, echoed
            if (deadWord(w)) continue;                 // a late offer of a connection the peer has left
            if (s.rejoining && !c.incoming && !s.pc?.remoteDescription) {
              // both rebuilt: the caller's offer stands -- said once more, for a callee whose run came back after my nine
              if (s.rejoinSdp) post(c, [word(c, "call", { n: person.name, s: c.seed, caps: caps(), video: !!c.video, sdp: { type: "offer", sdp: s.rejoinSdp }, reason: "rejoin" })]);
              continue;
            }
            await rebuildForRejoin(w);
          } else if ((!c || c.seed !== w.s) && await invoke("call_buried", { seed: w.s })) {
            post({ chat, epoch }, [word({ epoch }, "call-end")]);
          }
          continue;
        }
        if (c && c.seed === w.s && !c.incoming) continue;   // my own word, echoed
        if (Date.now() - (w.ts || 0) > LIFE_MS) { post({ chat, epoch }, [word({ epoch }, "call-end")]); continue; }
        await ringing(chat, w.s, !!w.video, w.n || "", w.sdp?.type === "offer" ? w.sdp : null, w.caps);
        continue;
      }
      const ring = secondRef.current, pk = parkedRef.current;
      if (ring && ring.epoch === epoch && ring.chat === chat) {
        if (w.ctrl === "call-end" || w.ctrl === "call-gone") dropSecond("ended");
        continue;
      }
      if (pk && pk.c.epoch === epoch && pk.c.chat === chat) { await hearParked(w); continue; }
      if (!c || c.epoch !== epoch || c.chat !== chat) continue;
      const key = JSON.stringify(w);
      if (s.seen?.has(key)) continue;
      s.seen?.add(key);
      if (w.ctrl === "call-ringing" && !c.incoming) {
        s.heard = true;
        invoke("call_heard", { talking: false, seed: c.seed });
        setCall((x) => (x ? { ...x, status: t("Ringing…") } : x));
      } else if (w.ctrl === "call-answer" && (!c.incoming || s.rejoining) && w.sdp && s.pc && !s.pc.remoteDescription && s.pc.signalingState === "have-local-offer") {
        // A RUN THAT CAME BACK READS THE LANE'S OLD WORDS TOO: an answer under a certificate the peer has left is buried (iOS: a word
        // of another connection)
        if (deadWord(w)) { mark("answer of a dead connection buried"); continue; }
        mark(`answer heard rejoining=${!!s.rejoining}`);
        s.heard = true;
        if (w.caps) s.peerRebuilds = !!w.caps.rejoin;
        learnCaps(s, w.caps);
        await s.pc.setRemoteDescription(w.sdp).then(() => notePeer(w.sdp.sdp)).catch(() => {});
        await drainIce();
        setCall((x) => (x ? { ...x, phase: "talk", status: t("Connecting…") } : x));
      } else if (w.ctrl === "call-restart") {
        learnCaps(s, w.caps);
        await restartHeard(w);
      } else if (w.ctrl === "call-restart-answer") {
        await restartAnswered(w);
      } else if (w.ctrl === "call-ice") {
        for (const cand of w.candidate ? [w.candidate] : w.candidates || []) await addIce(cand);
      } else if (w.ctrl === "call-room" && typeof w.reason === "string" && (c.phase === "talk" || s.reconnecting)) {
        if (w.reason.startsWith(ROOM_IN)) { s.roomAnswer?.(w.reason.slice(ROOM_IN.length)); continue; }
        // THE PEER GREW THIS CALL INTO A ROOM (iOS «call-room»): the group and the room stand here, my room key goes back on this
        // road, the call of two ends in silence and this side comes into the room by itself
        const [head, payload] = w.reason.split("\n");
        const back = payload ? await invoke("room_take_inline", { chat, head, payload }).catch(() => null) : null;
        if (!back) { mark("call-room unreadable: the call stays"); continue; }
        await post(c, [word(c, "call-room", { reason: ROOM_IN + back })]);
        mark("call-room: moving into the room");
        await finish("moved", false);
        await invoke("room_join", { chat: "grp:" + head.split("/")[0], video: false }).catch(() => {});
      } else if (w.ctrl === "call-video-ask") {
        setAsked(true);
      } else if (w.ctrl === "call-video-ok") {
        if (s.asking) { s.asking = false; clearTimeout(s.askTimer); setAsking(false); cameraIn("upgrade offered"); }
      } else if (w.ctrl === "call-video-no") {
        s.asking = false; clearTimeout(s.askTimer); setAsking(false);
        mark("video consent declined");
      } else if (w.ctrl === "call-video-end") {
        dropVideo(false);
      } else if (w.ctrl === "call-camera-off") {
        // THE PEER'S CAMERA RESTS (iOS 2304 «call-camera-off»): its cover stands at once; the last live camera left -- both sides
        // return to a voice call
        mark(`peer's camera rests mine=${s.camResting ? "resting" : "live"}`);
        s.peerCamOff = true;
        setCall((x) => (x ? { ...x, peerCamOff: true } : x));
        if (s.camResting) dropVideo(false);
      } else if (w.ctrl === "call-camera-on") {
        mark("peer's camera rises again");
        s.peerCamOff = false;
        setCall((x) => (x ? { ...x, peerCamOff: false } : x));
      } else if (w.ctrl === "call-hold" || w.ctrl === "call-resume") {
        setCall((x) => (x ? { ...x, heldByPeer: w.ctrl === "call-hold" } : x));
      } else if (w.ctrl === "call-screen-on") {
        // THE PEER SHOWS ITS SCREEN (iOS «call-screen-on»): it rides the standing video lane; a voice call shows a picture for it
        s.peerShareGrewVideo = !c.video;
        s.peerSharing = true;   // the recording draws a shared screen whole (iOS remoteFits)
        setCall((x) => (x ? { ...x, peerSharing: true } : x));
        setTimeout(() => markPicture("share seen", remoteVideo.current, st.current.pc), 4000);
      } else if (w.ctrl === "call-screen-off") {
        // the sharer alone knows what the call was before the share: «video: false» -- the picture goes with it
        const back = w.video === false || (w.video === undefined && s.peerShareGrewVideo);
        s.peerShareGrewVideo = false;
        s.peerSharing = false;
        setCall((x) => (x ? { ...x, peerSharing: false, video: back ? false : x.video } : x));
      } else if (w.ctrl === "call-end" || w.ctrl === "call-gone") {
        finish("remote", false);
      }
    }
  };

  /** THE CALL ON DISK (iOS writeHeldCall): a call standing with a peer that rebuilds, for the next run if this one dies. */
  const keepOnDisk = (s) => {
    const c = live.current;
    if (st.current !== s || !c || c.phase === "end" || !s.connectedAt || !s.peerRebuilds) return;
    invoke("call_hold", { record: JSON.stringify({ chat: c.chat, name: c.name, seed: c.seed, video: !!c.video, initiator: !c.incoming,
      startedAt: c.at, connectedAt: s.connectedAt, rebuilds: true, alive: Date.now(), rejoins: s.rejoins || 0,
      peers: (s.peerFPs || []).slice(-8) }) }).catch(() => {});
  };
  /** THE RUN GOES BACK INTO THE CALL ITS PROCESS HELD (iOS rejoinHeldCall): only a call that stood connected, with a peer that
   *  rebuilds in place, last known alive inside the peer's wait, and that no run went back into twice; the same seed, a new
   *  connection, «rejoin» on the lane -- nothing rings on either side. A call judged gone is told to the peer once. */
  const rejoinHeld = async (h) => {
    const age = Date.now() - (h.alive || 0);
    if (live.current || !(h.connectedAt > 0) || !h.rebuilds || (h.rejoins || 0) >= HELD_TRIES || age >= REJOIN_WINDOW_MS || !h.chat || !h.seed) {
      mark(`rejoin held not tried age_s=${Math.round(age / 1000)} tries=${h.rejoins || 0}`);
      await invoke("call_unhold").catch(() => {});
      if (h.chat && h.seed && !live.current) {
        const epoch = h.seed.slice(0, 16);
        post({ chat: h.chat, epoch }, [word({ epoch }, "call-gone")]);
        invoke("call_end", { chat: h.chat, seed: h.seed, video: !!h.video, incoming: !h.initiator,
                             seconds: Math.max(0, Math.round(((h.alive || 0) - h.connectedAt) / 1000)), missed: false }).catch(() => {});
      }
      return;
    }
    const c = { phase: "talk", chat: h.chat, name: h.name || "", seed: h.seed, epoch: h.seed.slice(0, 16), video: !!h.video, incoming: !h.initiator,
                status: t("Reconnecting…"), reconnecting: true, at: h.startedAt || Date.now() };
    const s = { seen: new Set(), connectedAt: h.connectedAt, answered: true, heard: true, peerRebuilds: true, rejoining: true, reconnecting: true,
                rebuilt: true, rejoins: (h.rejoins || 0) + 1, hadVideo: !!h.video,
                peerFPs: [...(h.peers || [])], deadFPs: new Set(h.peers || []) };
    st.current = s;
    live.current = c;
    setCall(c); setMuted(false); setHeld(false); setAsking(false); setAsked(false);
    mark(`rejoin held tx age_s=${Math.round(age / 1000)} video=${c.video} caller=${!c.incoming}`);
    await invoke("call_begin", { chat: c.chat, seed: c.seed, video: c.video, outgoing: false });
    keepOnDisk(s);
    s.deadline = setTimeout(() => { if (st.current === s && s.reconnecting) finish("rejoin-unanswered", true); },
                            Math.max(REJOIN_ANSWER_MS, (h.alive || 0) + REJOIN_WINDOW_MS - Date.now()));
    try {
      const pc = await connect(c);
      const offer = await pc.createOffer();
      const sdp = tune(offer.sdp, 64000);
      await pc.setLocalDescription({ type: "offer", sdp });
      s.rejoinSdp = sdp;
      sendRejoinOffer(pc, sdp, 0);
    } catch { finish("media", true); }
  };

  /** MY CAMERA JOINS THE STANDING CALL (iOS upgradeToVideo / enableMyVideo): the picture rides the video lane -- the standing one
   *  or a new one -- and a «media» re-offer carries it; the call is a video call from here. */
  const cameraIn = async (why) => {
    const s = st.current, c = live.current, pc = s.pc;
    if (!pc || !c || c.phase !== "talk" || s.stream?.getVideoTracks().length) return;
    let cam;
    try { cam = await navigator.mediaDevices.getUserMedia({ video: { width: 1280, height: 720, frameRate: 24 } }); }
    catch { mark("video: the camera would not open"); return; }
    const track = cam.getVideoTracks()[0];
    if (!track || st.current !== s || s.pc !== pc) { cam.getTracks().forEach((x) => x.stop()); return; }
    track.enabled = !s.held;
    s.stream.addTrack(track);
    s.hadVideo = true;
    const tr = pc.getTransceivers().find((x) => x.receiver?.track?.kind === "video" && !x.stopped);
    if (tr) {
      if (!s.share) await tr.sender.replaceTrack(track).catch(() => {});
      if (tr.direction !== "sendrecv") { tr.direction = "sendrecv"; tr.sender.setStreams?.(s.stream); }
    } else {
      pc.addTrack(s.share || track, s.stream);
    }
    setCall((x) => (x ? { ...x, video: true } : x));
    await offerAgain(false);
    mark(`video ${why}`);
    for (const ms of [4000, 9000]) setTimeout(() => { if (st.current === s) markPicture("picture seen", remoteVideo.current, s.pc); }, ms);
  };
  /** THE OTHER CAMERA (iOS switchCamera: the front and the back): the next camera of this computer takes the picture's place --
   *  the same lane, the same call, the peer sees the new picture without a word; the camera left stops. */
  const flipCamera = async () => {
    const s = st.current, c = live.current, pc = s.pc;
    const old = s.stream?.getVideoTracks()[0];
    if (!c || !c.video || !old || s.share) return;
    const cams = (await navigator.mediaDevices.enumerateDevices().catch(() => [])).filter((d) => d.kind === "videoinput");
    if (cams.length < 2) return;
    const at = cams.findIndex((d) => d.deviceId === old.getSettings().deviceId);
    const next = cams[(at + 1) % cams.length];
    let cam;
    try { cam = await navigator.mediaDevices.getUserMedia({ video: { deviceId: { exact: next.deviceId }, width: 1280, height: 720, frameRate: 24 } }); }
    catch { mark("camera: the other camera would not open"); return; }
    const track = cam.getVideoTracks()[0];
    if (!track || st.current !== s) { cam.getTracks().forEach((x) => x.stop()); return; }
    track.enabled = old.enabled;
    s.stream.removeTrack(old); old.stop(); s.stream.addTrack(track);
    const tr = pc?.getTransceivers().find((x) => x.sender?.track === old || (x.receiver?.track?.kind === "video" && !x.stopped));
    await tr?.sender.replaceTrack(track).catch(() => {});
    if (localVideo.current) localVideo.current.srcObject = s.stream;
    mark(`camera switched ${at + 1 > 0 ? at + 1 : "?"} -> ${((at + 1) % cams.length) + 1} of ${cams.length}`);
  };
  useEffect(() => {
    // how many cameras this computer has, asked when a video call stands (the key shows only when there is another)
    if (!call?.video) return;
    navigator.mediaDevices.enumerateDevices().then((l) => setCameras(l.filter((d) => d.kind === "videoinput").length)).catch(() => {});
  }, [call?.video]);
  /** THE CALL LEAVES PICTURES (iOS dropVideoMode): my camera stops, the lane rests, the call is a voice call again; told to the peer
   *  when this side chose it. A screen riding the lane keeps it. */
  const dropVideo = async (tell) => {
    const s = st.current, c = live.current, pc = s.pc;
    if (!c || !c.video || s.share) return;
    if (tell) await post(c, [word(c, "call-video-end")]);
    s.stream?.getVideoTracks().forEach((x) => { x.stop(); s.stream.removeTrack(x); });
    const tr = pc?.getTransceivers().find((x) => x.receiver?.track?.kind === "video" && !x.stopped);
    await tr?.sender.replaceTrack(null).catch(() => {});
    s.camResting = false; s.peerCamOff = false;
    setCall((x) => (x ? { ...x, video: false, camResting: false, peerCamOff: false } : x));
    mark(`video mode ended tell=${tell}`);
  };
  /** MY CAMERA RESTS, THE PEER'S PICTURE STAYS (iOS 2304 restMyCamera, the author's word 20.10 19:5x): my camera stops -- no light, no
   *  frames -- the lane falls silent, my picture wears my cover, and the peer is told so its cover of me stands at once (an old build
   *  buries the word and covers me when my frames stop). */
  const restCamera = async () => {
    const s = st.current, c = live.current, pc = s.pc;
    if (!c || !c.video || s.camResting || s.share) return;
    s.camResting = true;
    const tr = pc?.getTransceivers().find((x) => x.receiver?.track?.kind === "video" && !x.stopped);
    await tr?.sender.replaceTrack(null).catch(() => {});
    s.stream?.getVideoTracks().forEach((x) => { x.stop(); s.stream.removeTrack(x); });
    setCall((x) => (x ? { ...x, camResting: true } : x));
    await post(c, [word(c, "call-camera-off")]);
    mark("my camera rests, the peer's picture stays");
  };
  /** MY CAMERA RISES (iOS raiseMyCamera): a fresh camera into the same lane, and the peer told. */
  const raiseCamera = async () => {
    const s = st.current, c = live.current, pc = s.pc;
    if (!c || !c.video || !s.camResting) return;
    let cam;
    try { cam = await navigator.mediaDevices.getUserMedia({ video: { width: 1280, height: 720, frameRate: 24 } }); }
    catch { mark("camera: would not open again"); return; }
    const track = cam.getVideoTracks()[0];
    if (!track || st.current !== s) { cam.getTracks().forEach((x) => x.stop()); return; }
    s.camResting = false;
    s.stream?.addTrack(track);
    const tr = pc?.getTransceivers().find((x) => x.receiver?.track?.kind === "video" && !x.stopped);
    await tr?.sender.replaceTrack(track).catch(() => {});
    if (localVideo.current) localVideo.current.srcObject = s.stream;
    setCall((x) => (x ? { ...x, camResting: false } : x));
    await post(c, [word(c, "call-camera-on")]);
    mark("my camera rises again");
  };
  /** THE VIDEO KEY (iOS toggleVideo): a share ends first; a voice call asks the peer before any camera opens; a video call leaves
   *  pictures for both. */
  const toggleVideo = async () => {
    const s = st.current, c = live.current;
    if (!c) return;
    if (s.share) return stopShare();
    if (c.video) {
      // the second press rests my camera alone while the peer's picture lives; the last live camera leaving ends the video mode
      if (s.camResting) return raiseCamera();
      const theirsLive = s.remoteVideo?.getVideoTracks().some((x) => x.readyState === "live" && !x.muted);
      if (theirsLive && !s.peerCamOff) return restCamera();
      return dropVideo(true);
    }
    if (s.asking) return;
    s.asking = true; setAsking(true);
    await post(c, [word(c, "call-video-ask")]);
    mark("video consent asked");
    clearTimeout(s.askTimer);
    s.askTimer = setTimeout(() => { if (st.current === s && s.asking) { s.asking = false; setAsking(false); mark("video consent timeout"); } }, ASK_MS);
  };
  const answerAsk = async (yes) => {
    const s = st.current, c = live.current;
    setAsked(false);
    if (!c) return;
    if (yes) s.consentAt = Date.now();
    await post(c, [word(c, yes ? "call-video-ok" : "call-video-no")]);
    mark(`video consent ${yes ? "accepted" : "refused"}`);
  };
  /** THE CALL AS IT WAS SEEN (iOS MTCallTape.seen, the author's word 16.10.2026 18:27: «the video call must be recorded as I saw
   *  it»): their picture fills the frame -- a shared screen whole, on black -- and mine stands in its corner where and as large as
   *  the screen shows it, rounded with its rim, mirrored as the screen mirrors it; the frame takes the screen's shape at its birth. */
  const seenCanvas = (s) => {
    const big = remoteVideo.current, mini = localVideo.current;
    const box = big?.parentElement?.getBoundingClientRect() || { width: 1280, height: 720, left: 0, top: 0 };
    const k = Math.min(1, 1280 / Math.max(box.width, box.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(2, Math.round(box.width * k / 2) * 2); canvas.height = Math.max(2, Math.round(box.height * k / 2) * 2);
    const g = canvas.getContext("2d");
    const place = (v, x, y, w, h, fit, mirror) => {
      const vw = v.videoWidth, vh = v.videoHeight;
      if (!vw || !vh) return;
      const q = fit ? Math.min(w / vw, h / vh) : Math.max(w / vw, h / vh);
      g.save(); g.beginPath(); g.rect(x, y, w, h); g.clip();
      g.translate(x + w / 2, y + h / 2); if (mirror) g.scale(-1, 1);
      g.drawImage(v, -vw * q / 2, -vh * q / 2, vw * q, vh * q);
      g.restore();
    };
    let frames = 0;
    const draw = () => {
      g.fillStyle = "#000"; g.fillRect(0, 0, canvas.width, canvas.height);
      if (big?.srcObject) place(big, 0, 0, canvas.width, canvas.height, !!s.peerSharing, false);
      const r = mini?.srcObject && mini.getBoundingClientRect();
      if (r && r.width > 0) {
        const x = (r.left - box.left) * k, y = (r.top - box.top) * k, w = r.width * k, h = r.height * k, rad = 12 * k;
        g.save(); g.beginPath(); g.roundRect(x - 1, y - 1, w + 2, h + 2, rad + 1); g.fillStyle = "rgba(255,255,255,0.25)"; g.fill();
        g.beginPath(); g.roundRect(x, y, w, h, rad); g.clip();
        place(mini, x, y, w, h, false, !s.share); g.restore();
      }
      frames += 1;
    };
    draw();
    const timer = setInterval(draw, 1000 / 24);
    return { stream: canvas.captureStream(24), stop: () => clearInterval(timer), frames: () => frames, size: `${canvas.width}x${canvas.height}` };
  };
  /** THE RECORDING REACHES THE CHAT WHOEVER RECORDS (iOS 2304 MontanaCall 1331-1338, the author's word 20.10.2026 19:5x MSK): the
   *  caller sends it, and the callee does when the caller does not record by itself -- one copy in the chat, never none. */
  const sendsToChat = (s, c) => !c.incoming || !(s.peerRec === true && mayRecord(mine.rec, mine.lv, s.peerLv));
  /** THE RECORDING BEGINS (iOS MTCallRecording.begin): both voices mixed -- mine as it leaves, theirs as it comes -- and in a video
   *  call the call as it was seen (seenCanvas), into an MP4; the chat is told first, in the words iOS writes (the caller's recording
   *  comes to the chat, the callee's stays here). */
  const startTape = async () => {
    const s = st.current, c = live.current;
    if (!c || c.phase !== "talk" || !s.connectedAt || s.tape) return;
    if (!mayRecord(s.peerRec, s.peerLv, mine.lv)) { mark("record forbidden by their switch"); return; }
    try {
      const ctx = new AudioContext();
      const mix = ctx.createMediaStreamDestination();
      for (const stream of [s.stream, s.remoteAudio]) {
        if (stream?.getAudioTracks().length) ctx.createMediaStreamSource(new MediaStream(stream.getAudioTracks())).connect(mix);
      }
      const seen = c.video ? seenCanvas(s) : null;
      const picture = seen ? seen.stream.getVideoTracks()[0] : null;
      const tracks = [...mix.stream.getAudioTracks(), ...(picture ? [picture] : [])];
      const type = picture ? "video/mp4;codecs=avc1.42E01E,mp4a.40.2" : "audio/mp4;codecs=mp4a.40.2";
      const recorder = new MediaRecorder(new MediaStream(tracks), MediaRecorder.isTypeSupported(type) ? { mimeType: type } : {});
      const parts = [];
      recorder.ondataavailable = (e) => { if (e.data?.size) parts.push(e.data); };
      recorder.start(1000);
      s.tape = { ctx, recorder, parts, video: !!picture, seen, at: Date.now() };
      setTaping(true);
      mark(`record start video=${!!picture}${seen ? " seen=" + seen.size : ""}`);
      const notice = !sendsToChat(s, c)
        ? t("This computer is recording the call locally. Only the caller sends a recording to the chat.")
        : t("This call is being recorded. The recording will be sent to this chat after the call.");
      invoke("chat_send", { chat: c.chat, text: notice, qt: null, qm: null }).catch(() => {});
    } catch {
      mark("record refused");
    }
  };
  /** THE RECORDING ENDS (iOS finish + export): the caller's goes to the chat as «Запись звонка», the callee's is kept in this
   *  computer's own folder of recordings. */
  const stopTape = (s = st.current, c = live.current) => {
    const tape = s.tape;
    if (!tape || !c) return;
    s.tape = null;
    setTaping(false);
    const secs = Math.round((Date.now() - tape.at) / 100) / 10;
    tape.seen?.stop();
    tape.recorder.onstop = async () => {
      tape.ctx.close().catch(() => {});
      const blob = new Blob(tape.parts, { type: tape.video ? "video/mp4" : "audio/mp4" });
      mark(`record stop bytes=${blob.size} secs=${secs} sent=${sendsToChat(s, c)}${tape.seen ? " frames=" + tape.seen.frames() + " seen=" + tape.seen.size : ""}`);
      if (!blob.size) return;
      const ext = tape.video ? "mp4" : "m4a";
      if (sendsToChat(s, c)) {
        const file = new File([blob], `call.${ext}`, { type: tape.video ? "video/mp4" : "audio/mp4" });
        sendFile(c.chat, file, t("Call recording"), null, tape.video ? { du: secs } : { k: "aud", du: secs }).catch(() => mark("record send refused"));
      } else {
        invoke("recording_keep", new Uint8Array(await blob.arrayBuffer()), { headers: { ext } }).catch(() => mark("record keep refused"));
      }
    };
    try { tape.recorder.stop(); } catch { /* a recorder already stopped */ }
  };

  /** HOLD (iOS softHold): the call stays on the screen; my voice and picture sleep, theirs too, and the peer is told. */
  const toggleHold = async () => {
    const s = st.current, c = live.current, pc = s.pc;
    if (!c || !pc) return;
    const on = !s.held;
    s.held = on;
    s.stream?.getAudioTracks().forEach((x) => (x.enabled = !on && !s.muted));
    s.stream?.getVideoTracks().forEach((x) => (x.enabled = !on));
    pc.getReceivers().forEach((r) => { if (r.track) r.track.enabled = !on; });
    setHeld(on);
    await post(c, [word(c, on ? "call-hold" : "call-resume")]);
    mark(`hold ${on ? "on" : "off"}`);
  };

  /** SHOW MY SCREEN (iOS startScreenShare): Windows' own picker chooses the screen or the window; the picture rides the standing
   *  video lane in the camera's place, and a voice call grows the lane by a «media» re-offer; «call-screen-on» tells the peer. */
  const startShare = async () => {
    const s = st.current, c = live.current, pc = s.pc;
    if (!pc || !c || c.phase !== "talk" || !s.connectedAt || s.share) return;
    let screen;
    try { screen = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 15 }, audio: false }); } catch { return; }   // nothing chosen
    const track = screen.getVideoTracks()[0];
    if (!track || st.current !== s || s.pc !== pc) { screen.getTracks().forEach((x) => x.stop()); return; }
    track.contentHint = "detail";
    s.share = track;
    s.audioBeforeShare = !c.video;
    let tr = pc.getTransceivers().find((x) => x.receiver?.track?.kind === "video" && !x.stopped);
    let grow = false;
    if (tr) {
      await tr.sender.replaceTrack(track).catch(() => {});
      if (tr.direction !== "sendrecv" && tr.direction !== "sendonly") { tr.direction = "sendrecv"; tr.sender.setStreams?.(s.stream); grow = true; }
    } else {
      pc.addTrack(track, s.stream);
      grow = true;
    }
    if (grow) await offerAgain(false);
    track.onended = () => stopShare();   // the system's own «stop sharing»
    mark(`share started surface=${track.getSettings?.().displaySurface || "-"} grew=${grow}`);
    await post(c, [word(c, "call-screen-on")]);
    setSharing(true);
  };
  /** STOP SHOWING IT (iOS stopScreenShare): the camera returns into the same lane, or the lane rests; the peer is told what the
   *  call was before the share. */
  const stopShare = async () => {
    const s = st.current, c = live.current, pc = s.pc;
    const track = s.share;
    if (!track) return;
    s.share = null;
    track.onended = null; track.stop();
    const tr = pc?.getTransceivers().find((x) => x.sender.track === track || (x.receiver?.track?.kind === "video" && !x.stopped));
    const cam = s.stream?.getVideoTracks()[0] || null;
    await tr?.sender.replaceTrack(cam).catch(() => {});
    mark(`share stopped camera_back=${!!cam}`);
    setSharing(false);
    if (c && c.phase !== "end") await post(c, [word(c, "call-screen-off", { video: !s.audioBeforeShare })]);
  };

  // THE CALL'S SECONDS ARE COINS (iOS MTCallMint, the author's word 14.10.2026): a recorded call mints them, one not recorded
  // burns them -- each tick names the seconds talked, and Rust takes the ones not taken yet
  useEffect(() => {
    const c = call, s = st.current;
    if (!c || c.phase !== "talk" || !s.connectedAt) return;
    const secs = Math.floor((now - s.connectedAt) / 1000);
    if (secs > 0) invoke("call_coins", { call: c.epoch, seconds: secs, recording: !!s.tape || callRecorded(s) }).catch(() => {});
  }, [now]);

  useEffect(() => {
    const stops = [];
    let gone = false;
    const on = (name, f) => listen(name, (e) => f(e.payload)).then((u) => { if (gone) u(); else stops.push(u); });
    on("montana://call", (p) => hear(p.chat, p.epoch, p.words));
    on("montana://ring", (r) => ringing(r.chat, r.seed, r.video, r.name, null));
    const startEvent = (e) => start(e.detail.chat, e.detail.name, e.detail.video);
    window.addEventListener("montana-call", startEvent);
    const tick = setInterval(() => setNow(Date.now()), 1000);
    invoke("call_held").then((r) => { if (!gone && r) { try { rejoinHeld(JSON.parse(r)); } catch { invoke("call_unhold").catch(() => {}); } } }).catch(() => {});
    return () => { gone = true; stops.forEach((u) => u()); window.removeEventListener("montana-call", startEvent); clearInterval(tick); };
  }, []);

  // a picture element born later (a share into a voice call) gets the stream already held
  useLayoutEffect(() => {
    const s = st.current;
    if (remoteVideo.current && s.remoteVideo && remoteVideo.current.srcObject !== s.remoteVideo) remoteVideo.current.srcObject = s.remoteVideo;
    if (remoteAudio.current && s.remoteAudio && remoteAudio.current.srcObject !== s.remoteAudio) remoteAudio.current.srcObject = s.remoteAudio;
    if (localVideo.current && s.stream && localVideo.current.srcObject !== s.stream) localVideo.current.srcObject = s.stream;
  });

  callDeeds = { unfold: () => fold(false, "handset"), end: () => finish("hangup", true) };
  if (!call) return null;
  const s = st.current;
  const foldable = call.phase !== "in" && call.phase !== "end";
  const isFolded = folded && foldable;
  const secs = s.connectedAt ? Math.floor((now - s.connectedAt) / 1000) : 0;
  const kind = call.video ? t("Montana video call") : t("Montana voice call");
  const line = call.phase === "in" ? "" : call.reconnecting ? t("Reconnecting…")
    : call.phase === "talk" && s.connectedAt ? `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}`
    : call.phase === "end" ? call.status : `${kind} — ${call.status}`;
  const toggleMute = () => { const m = !muted; s.muted = m; s.stream?.getAudioTracks().forEach((x) => (x.enabled = !m && !s.held)); setMuted(m); };
  /** ADD TO THE CALL (iOS grow): the people chosen and the peer go into a room of a group born for them; the call stands until the
   *  peer says it comes, then ends by the rule and the room takes the voices over. */
  const growInto = async (chats) => {
    const c = live.current;
    setAdding(null);
    if (!c || !chats.length) return;
    let word_;
    try { word_ = await invoke("room_grow", { peer: c.chat, chats, video: !!c.video }); } catch { return; }
    const reply = await new Promise((done) => {
      st.current.roomAnswer = done;
      post(c, [word(c, "call-room", { reason: word_ })]);
      setTimeout(() => done(null), ROOM_ANSWER_MS);
    });
    st.current.roomAnswer = null;
    mark(`call grows into a room peer=${reply ? "in" : "late"}`);
    await finish("moved", true);
    await invoke("room_grown", { reply }).catch(() => {});
  };
  const openAdding = async () => {
    const people = await invoke("room_grow_people", { chat: call.chat }).catch(() => []);
    setAdding({ people, chosen: new Set() });
  };
  const clockNow = s.connectedAt ? `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}` : (call.status || "");
  return (<>
    {/* THE FOLDED CALL (iOS CallOverlayView.pillBody): the green capsule -- the call's glyph and its clock -- takes the person back to
        it; the red round ends it; above the window's foot, never over a name */}
    {/* the pill floats only where no name lives (iOS MTMinimizedCallLayer): not over the chats' list, whose row of that person wears
        the handsets; over an open chat it stays until the chat's head wears them too */}
    {isFolded && !pillHidden && (
      <div className="call-pill-row" role="group" aria-label={kind}>
        <button className="call-pill" onClick={() => fold(false, "pill")} aria-label={`${kind} ${clockNow}`}>
          <Glyph name={call.video ? "video" : "phone"} size={16} color="#fff" /><b className="digits">{clockNow}</b>
        </button>
        <button className="call-pill-end" onClick={() => finish("hangup", true)} aria-label={t("End")}><Glyph name="calls" size={16} color="#fff" /></button>
      </div>
    )}
    <div className={"call-screen" + (isFolded ? " folded" : "")} role="dialog" aria-label={kind} aria-hidden={isFolded || undefined}
         onPointerDown={(e) => { stroke.current = e.target.closest("button") ? null : { x: e.clientX, y: e.clientY }; }}
         onPointerUp={(e) => {
           const o = stroke.current; stroke.current = null;
           // THE FOLD BY A STROKE DOWN (iOS foldBySwipe): more than 80 down, more down than across
           if (o && foldable && e.clientY - o.y > 80 && Math.abs(e.clientX - o.x) < e.clientY - o.y) fold(true, "swipe");
         }}>
      <audio ref={remoteAudio} autoPlay />
      {/* THE BACK MARK (iOS MontanaCallMark chevron.down «Back»): the call folds into the app */}
      {foldable && (
        <button className="glass-mark call-back" onClick={() => fold(true, "back")} aria-label={t("Back")}>
          <Glyph name="chevronDown" size={18} color="#fff" />
        </button>
      )}
      {(call.video || call.peerSharing) && (
        <div className={"call-remote" + (call.peerSharing ? " screen" : "")} role={call.peerSharing ? "img" : undefined} aria-label={call.peerSharing ? t("Screen") : undefined}>
          <video ref={remoteVideo} autoPlay playsInline style={call.peerCamOff && !call.peerSharing ? { visibility: "hidden" } : undefined} />
        </div>
      )}
      {call.video && !call.peerSharing && <video ref={localVideo} className="call-local" autoPlay playsInline muted style={call.camResting ? { visibility: "hidden" } : undefined} />}
      <div className="call-head">
        {call.phase === "in" && <div className="call-kind"><span className="seen-dot live" />{kind}</div>}
        <Face chat={call.chat} version={0} size={96} />
        <div className="call-name">{chatName(call.name)}</div>
        <div className="call-line" aria-live="polite">{line}</div>
        {sharing && <div className="call-sharing">{t("You are sharing your screen")}</div>}
        {taping && <div className="call-taping" role="status"><span className="rec-dot" />{t("Recording")}</div>}
        {(held || call.heldByPeer) && call.phase === "talk" && <div className="call-held">{t("On hold")}</div>}
        {parked && <div className="call-parked" role="status">{`${chatName(parked.name)}: ${t("On hold")}`}</div>}
        {second && (
          <div className="call-ask call-second" role="group" aria-label={`${chatName(second.name)} ${t(second.video ? "is calling with video" : "is calling")}`}>
            <span><b>{chatName(second.name)}</b> {t(second.video ? "is calling with video" : "is calling")}</span>
            <button className="call-ask-no" onClick={() => dropSecond("declined")}>{t("Decline")}</button>
            <button className="call-ask-yes" onClick={() => answerSecond(false)}>{t("End & Accept")}</button>
            <button className="call-ask-yes" onClick={() => answerSecond(true)}>{t("Hold & Accept")}</button>
          </div>
        )}
        {asked && call.phase === "talk" && (
          <div className="call-ask" role="group" aria-label={`${chatName(call.name)} ${t("is calling with video")}`}>
            <span><b>{chatName(call.name)}</b> {t("is calling with video")}</span>
            <button className="call-ask-yes" onClick={() => answerAsk(true)}>{t("Accept")}</button>
            <button className="call-ask-no" onClick={() => answerAsk(false)}>{t("Decline")}</button>
          </div>
        )}
      </div>
      <div className="call-keys">
        {call.phase === "in" ? (
          <>
            <button className="call-key red" onClick={() => finish("declined", true)} aria-label={t("Decline")}><Glyph name="calls" size={28} color="#fff" /><span>{t("Decline")}</span></button>
            <button className="call-key green" onClick={accept} aria-label={t("Accept")}><Glyph name="calls" size={28} color="#fff" /><span>{t("Accept")}</span></button>
          </>
        ) : call.phase !== "end" ? (
          <>
            <button className={"call-key" + (muted ? " on" : "")} onClick={toggleMute} aria-label={t("Mute")}><Glyph name="mic" size={26} color="#fff" /><span>{t("Mute")}</span></button>
            {call.phase === "talk" && s.connectedAt && <button className={"call-key" + ((call.video && !call.camResting) || asking ? " on" : "")} onClick={toggleVideo} aria-label={t("Video")} aria-pressed={(!!call.video && !call.camResting) || asking}><Glyph name="video" size={26} color="#fff" /><span>{t("Video")}</span></button>}
            {call.phase === "talk" && call.video && cameras > 1 && !sharing && <button className="call-key" onClick={flipCamera} aria-label={t("Switch camera")}><Glyph name="restore" size={26} color="#fff" /><span>{t("Switch camera")}</span></button>}
            {call.phase === "talk" && s.connectedAt && (parked
              ? <button className="call-key" onClick={swap} aria-label={t("Swap")}><Glyph name="pauseFill" size={26} color="#fff" /><span>{t("Swap")}</span></button>
              : <button className={"call-key" + (held ? " on" : "")} onClick={toggleHold} aria-label={t("Hold")} aria-pressed={held}><Glyph name="pauseFill" size={26} color="#fff" /><span>{t("Hold")}</span></button>)}
            {call.phase === "talk" && s.connectedAt && (taping || mayRecord(s.peerRec, s.peerLv, mine.lv)) && <button className={"call-key" + (taping ? " on" : "")} onClick={taping ? () => stopTape() : startTape} aria-label={t(taping ? "Stop recording" : "Record")} aria-pressed={taping}><Glyph name="circle" size={26} color={taping ? "#ff453a" : "#fff"} /><span>{t(taping ? "Stop recording" : "Record")}</span></button>}
            {call.phase === "talk" && s.connectedAt && <button className={"call-key" + (sharing ? " on" : "")} onClick={sharing ? stopShare : startShare} aria-label={t("Broadcast")} aria-pressed={sharing}><Glyph name="antenna" size={26} color="#fff" /><span>{t("Broadcast")}</span></button>}
            {call.phase === "talk" && s.connectedAt && <button className="call-key" onClick={openAdding} aria-label={t("Add to Call")}><Glyph name="plus" size={26} color="#fff" /><span>{t("Add to Call")}</span></button>}
            <button className="call-key red" onClick={() => finish("hangup", true)} aria-label={t("End")}><Glyph name="calls" size={28} color="#fff" /><span>{t("End")}</span></button>
          </>
        ) : null}
      </div>
      {adding && (
        <div className="menu-shade" onClick={() => setAdding(null)}>
          <div className="room-invite" onClick={(e) => e.stopPropagation()} role="dialog" aria-label={t("Add to Call")}>
            <header className="room-invite-head">
              <button className="glass-mark" onClick={() => setAdding(null)} aria-label={t("Cancel")}><Glyph name="close" size={16} color="rgb(204,204,204)" /></button>
              <b>{t("Add to Call")}</b>
              <button className="glass-mark" onClick={() => growInto([...adding.chosen])} aria-label={t("Done")}><Glyph name="check" size={16} color="rgb(204,204,204)" /></button>
            </header>
            {adding.people.map(([ref, name]) => {
              const on = adding.chosen.has(ref);
              return (
                <button key={ref} className="room-person" aria-pressed={on} aria-label={`${t("Add to Call")}: ${name}`}
                        onClick={() => setAdding((a) => { const n = new Set(a.chosen); if (n.has(ref)) n.delete(ref); else if (n.size < ROOM_PLACES) n.add(ref); return { ...a, chosen: n }; })}>
                  <span className="room-face">{(name || "?").slice(0, 1).toUpperCase()}</span><span className="grow">{name}</span>
                  <span className={"tick" + (on ? " on" : "")} />
                </button>
              );
            })}
            <div className="room-invite-foot">{t("Up to %lld people on a call, you included. Everyone chosen is invited into the call.").replace("%lld", 13)}</div>
          </div>
        </div>
      )}
    </div>
  </>);
}

/** Calls someone from anywhere in the window (the chat's bar, the calls' log). */
export function callTo(chat, name, video) {
  window.dispatchEvent(new CustomEvent("montana-call", { detail: { chat, name, video } }));
}
