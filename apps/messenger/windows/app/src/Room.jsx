import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { t } from "./strings.js";
import { sendFile } from "./Media.jsx";
import { Glyph } from "./TopBar.jsx";

// A GROUP'S LIVE ROOM IN THE WINDOW (iOS MTGroupRoom's pairs, MTRoomScreen, MTRoomBar, MTRoomMark, MTRoomInviteSheet): Rust holds
// the room and its words; here stand the pairs -- one WebRTC call of two per seat, the later of the two offering -- their beat,
// the voices and the screen.

const CAPACITY = 13;
/** A line of the room's machinery for a check's own diary (Rust writes it only under MONTANA_TRACE). */
const mark = (line) => { invoke("trace", { line: "room " + line }).catch(() => {}); };
const LOST_MS = 30000, BIRTH_MS = 60000, GONE_MS = 180000, SPEAKING = 0.04;

/** A connection's name is its certificate (iOS fingerprint). */
function fingerprint(sdp) {
  const m = /^a=fingerprint:(.*)$/m.exec(sdp || "");
  return m ? m[1].trim().toLowerCase() : null;
}
/** The later of two to come in: the moment first, the seat for a tie (iOS later). */
const later = (a, b) => (a[0] !== b[0] ? a[0] > b[0] : a[1] > b[1]);

function config(pass) {
  const servers = [];
  if (pass?.stun?.length) servers.push({ urls: pass.stun });
  if (pass?.uris?.length) {
    const rank = (u) => (u.startsWith("turns:") && u.includes(":443") ? 0 : u.startsWith("turns:") ? 1 : u.includes("transport=tcp") ? 2 : 3);
    servers.push({ urls: [...pass.uris].sort((a, b) => rank(a) - rank(b)), username: pass.username, credential: pass.credential });
  }
  return { iceServers: servers, bundlePolicy: "max-bundle", iceTransportPolicy: "all" };
}

// ───────────────────────────── the engine: one, for the window ─────────────────────────────

const E = { rooms: {}, live: null, shown: false, muted: false, camera: false, screen: false, screenTrack: null, note: null,
            pairs: new Map(), stream: null, video: null, level: 0, pass: null, genFloor: {}, unlinked: {}, focus: null, tick: 0 };
const ears = new Set();
function emit() { E.tick++; ears.forEach((f) => f(E.tick)); }
export function useRoom() {
  const [, set] = useState(0);
  useEffect(() => { ears.add(set); return () => { ears.delete(set); }; }, []);
  return E;
}
const sayLine = (key) => { E.note = t(key); emit(); setTimeout(() => { if (E.note === t(key)) { E.note = null; emit(); } }, 4000); };
const stage = (seat) => E.live && (E.live.kind === "call" || seat === E.live.owner);
const send = (p, c, extra = {}) => invoke("room_send", { seat: p.seat, c, g: p.gen, sdp: extra.sdp ?? null, ice: extra.ice ?? null }).catch(() => false);
window.montanaRoomBusy = () => !!E.live;

/** What Rust said of the rooms: the bars' book and the room in hand; the pairs follow the people in it. */
async function state(v) {
  const was = E.live;
  E.rooms = v?.rooms || {};
  E.live = v?.live || null;
  mark(`state live=${E.live ? E.live.people.map((x) => x.seat.slice(0, 4) + (x.key ? "k" : "")).join(",") : "-"} pairs=${[...E.pairs.keys()].map((x) => x.slice(0, 4)).join(",")}`);
  if (!E.live) {
    if (was) closeAll();
    emit();
    return;
  }
  if (!was || was.id !== E.live.id) await enter();
  const me = E.live.me;
  const people = new Map(E.live.people.map((x) => [x.seat, x]));
  for (const [seat, p] of E.pairs) {
    const x = people.get(seat);
    if (!x || !(stage(seat) || stage(me))) drop(seat);
    else if (x.at !== p.moment) { drop(seat); delete E.genFloor[seat]; }   // a seat that came in again is another pair
  }
  for (const x of E.live.people) {
    if (x.seat === me || !(stage(x.seat) || stage(me))) continue;
    if (!E.pairs.has(x.seat)) pairUp(x);
    const p = E.pairs.get(x.seat);
    // A KEY THAT CAME LETS MY WAITING OFFER GO AT ONCE (iOS follow)
    if (p && x.key && p.offerer && !p.answered && p.lastOffer && !p.keyed) { p.keyed = true; p.offeredAt = Date.now(); send(p, "offer", { sdp: p.lastOffer }); }
    if (p) p.keyed = p.keyed || x.key;
  }
  E.pairs.forEach(tune);   // one more or one less: the pictures each watcher gets are measured again
  emit();
}

async function enter() {
  E.shown = true; E.muted = false; E.camera = false; E.focus = null; E.genFloor = {}; E.unlinked = {};
  E.pass = await invoke("turn_cred").catch(() => null);
  if (stage(E.live.me)) {
    try {
      E.stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } });
    } catch {
      E.stream = null; E.muted = true;
      sayLine("Microphone access is off");
    }
  }
  E.pairs.forEach(dress);   // pairs born while the microphone opened take its voice now
  if (E.live?.video && stage(E.live.me)) await setCamera(true);   // a video chat comes in with the camera (iOS enter)
}

/** A picture's size on a tile and the frames under it, for a check's diary. */
function markPicture(p, what) {
  const el = p.el, pc = p.pc;
  if (!pc) return;
  pc.getStats().then((stats) => {
    let got = 0;
    stats.forEach((r) => { if (r.type === "inbound-rtp" && r.kind === "video") got += r.framesDecoded || 0; });
    mark(`picture ${p.seat.slice(0, 4)} ${what} ${el ? `${el.videoWidth}x${el.videoHeight}` : "none"} in=${got}`);
  }).catch(() => {});
}

function closeAll() {
  if (E.tape) stopTape();   // the room's end ends its recording, and the recording goes to the group's chat
  for (const seat of [...E.pairs.keys()]) drop(seat);
  E.stream?.getTracks().forEach((x) => x.stop());
  E.video?.getTracks().forEach((x) => x.stop());
  if (E.screenTrack) { E.screenTrack.onended = null; E.screenTrack.stop(); }
  E.stream = null; E.video = null; E.shown = false; E.camera = false; E.screen = false; E.screenTrack = null;
}

function pairUp(x) {
  const me = E.live.me, mine = E.live.people.find((y) => y.seat === me);
  const p = { seat: x.seat, moment: x.at, offerer: later([mine?.at ?? E.live.since, me], [x.at, x.seat]), gen: E.genFloor[x.seat] || 0,
              pc: null, channel: null, linked: false, everLinked: false, lostAt: 0, bornAt: Date.now(), heldIce: [], outIce: [], flush: 0,
              lastOffer: null, lastAnswer: null, offeredAt: 0, offers: 0, answered: false, restarts: 0, remoteFP: null,
              muted: false, cameraOn: false, screen: false, wantsMe: false, level: 0, stream: null, el: null, keyed: x.key };
  if (!E.unlinked[x.seat]) E.unlinked[x.seat] = Date.now();
  E.pairs.set(x.seat, p);
  if (p.offerer) offer(p);
}

function build(p) {
  if (p.pc) return p.pc;
  const pc = new RTCPeerConnection(config(E.pass));
  p.pc = pc;
  pc.onicecandidate = (e) => {
    if (!e.candidate || p.pc !== pc) return;
    p.outIce.push({ s: e.candidate.candidate, i: e.candidate.sdpMLineIndex ?? 0, m: e.candidate.sdpMid ?? undefined });
    if (p.flush) return;
    // the candidates leave in small bundles: one post for many, the first bundle at once
    p.flush = setTimeout(() => { p.flush = 0; if (p.pc !== pc || !p.outIce.length) return; const batch = p.outIce.splice(0); send(p, "ice", { ice: batch }); }, 150);
  };
  pc.oniceconnectionstatechange = () => { if (p.pc === pc) pairState(p, pc.iceConnectionState); };
  pc.ontrack = (e) => {
    if (p.pc !== pc) return;
    p.stream = e.streams[0] || new MediaStream([e.track]);
    emit();
  };
  pc.ondatachannel = (e) => { if (p.pc !== pc) return; p.channel = e.channel; wire(p, e.channel); };
  return pc;
}

/** The pair's lines carry what this machine gives: its voice where it speaks, its picture -- the camera or the screen -- where it
 *  shows (iOS dress / picture). */
function dress(p) {
  const pc = p.pc;
  if (!pc) return;
  const speaks = stage(E.live?.me);
  const audio = speaks ? E.stream?.getAudioTracks()[0] || null : null;
  const video = !speaks ? null : E.screen ? E.screenTrack : E.camera ? E.video?.getVideoTracks()[0] || null : null;
  for (const tr of pc.getTransceivers()) {
    const kind = tr.receiver.track?.kind;
    const want = kind === "audio" ? audio : kind === "video" ? video : null;
    if (tr.sender.track !== want) tr.sender.replaceTrack(want).catch(() => {});
    try { tr.direction = speaks ? "sendrecv" : "recvonly"; } catch { /* a stopped line */ }
  }
  tune(p);
}

/** THE PICTURE EACH WATCHER GETS (iOS tune): small in the grid; whole when it shows me large, when we are two, on a stream, or a
 *  screen -- the screen sharper and slower; the voice is never the victim, the picture gives way first. */
function tune(p) {
  const sender = p.pc?.getTransceivers().find((x) => x.receiver.track?.kind === "video")?.sender;
  if (!sender || !E.live) return;
  const params = sender.getParameters();
  const enc = params.encodings?.[0];
  if (!enc) return;
  const whole = E.screen || E.live.kind === "live" || p.wantsMe || E.pairs.size <= 1;
  const want = { maxBitrate: E.screen ? 1200000 : whole ? 700000 : 160000, scaleResolutionDownBy: whole ? 1 : 2, maxFramerate: E.screen ? 15 : whole ? 24 : 15 };
  if (Object.keys(want).every((k) => enc[k] === want[k])) return;
  Object.assign(enc, want);
  sender.setParameters(params).catch(() => {});
}

async function offer(p, restart = false) {
  const pc = build(p);
  if (!pc.getTransceivers().length) {
    pc.addTransceiver("audio", { direction: "sendrecv" });
    pc.addTransceiver("video", { direction: "sendrecv" });
    p.channel = pc.createDataChannel("room", { ordered: true });
    wire(p, p.channel);
  }
  dress(p);
  if (restart) { p.gen += 1; p.answered = false; p.restarts += 1; p.offers = 0; }
  try {
    const o = await pc.createOffer({ iceRestart: restart });
    await pc.setLocalDescription(o);
    if (p.pc !== pc) return;
    p.lastOffer = o.sdp; p.offeredAt = Date.now(); p.offers += 1;
    send(p, "offer", { sdp: o.sdp });
  } catch { /* the beat offers again */ }
}

async function answer(p, sdp, gen) {
  // A CONNECTION BUILT ANEW BY THE LATER ONE: another certificate is another connection -- the old one here is let go
  const fp = fingerprint(sdp);
  if (fp && p.remoteFP && fp !== p.remoteFP && p.pc) {
    p.channel?.close(); p.channel = null; p.pc.close(); p.pc = null; p.stream = null; p.lastAnswer = null; p.linked = false;
  }
  // a repeat of an offer already answered: the same answer again -- the first may have died on the way
  if (gen === p.gen && p.lastAnswer) { send(p, "answer", { sdp: p.lastAnswer }); return; }
  const pc = build(p);
  try {
    await pc.setRemoteDescription({ type: "offer", sdp });
    p.gen = gen; p.remoteFP = fp;
    for (const c of p.heldIce.splice(0)) await pc.addIceCandidate(c).catch(() => {});
    dress(p);
    const a = await pc.createAnswer();
    await pc.setLocalDescription(a);
    if (p.pc !== pc) return;
    p.lastAnswer = a.sdp;
    send(p, "answer", { sdp: a.sdp });
  } catch { /* the offerer offers again */ }
}

/** A pair word from the lane (iOS laneWord, the window's half). */
async function signal(w) {
  const p = E.pairs.get(w.from);
  if (w.c !== "ice") mark(`lane ${w.c} from=${String(w.from).slice(0, 4)} pair=${!!p} g=${w.g}`);
  if (!E.live || !p) return;
  if (w.c === "offer" && !p.offerer && w.sdp && w.g >= p.gen) await answer(p, w.sdp, w.g);
  else if (w.c === "answer" && p.offerer && w.sdp && w.g === p.gen && !p.answered && p.pc) {
    p.answered = true;
    try {
      await p.pc.setRemoteDescription({ type: "answer", sdp: w.sdp });
      for (const c of p.heldIce.splice(0)) await p.pc.addIceCandidate(c).catch(() => {});
    } catch { p.answered = false; }
  } else if (w.c === "ice" && w.g >= p.gen) {
    for (const c of w.ice || []) {
      const cand = { candidate: c.s, sdpMLineIndex: c.i, sdpMid: c.m ?? null };
      if (p.pc?.remoteDescription && w.g === p.gen) await p.pc.addIceCandidate(cand).catch(() => {});
      else if (p.heldIce.length < 64) p.heldIce.push(cand);
    }
  } else if (w.c === "bye" && !p.linked) {
    vanish(p.seat, false);
  }
}

function pairState(p, st) {
  if (!E.live) return;
  mark(`pair ${p.seat.slice(0, 4)} ice=${st} offerer=${p.offerer}`);
  if (st === "connected" || st === "completed") {
    p.linked = true; p.everLinked = true; p.lostAt = 0; p.restarts = 0;
    delete E.unlinked[p.seat];
    invoke("room_do", { act: "linked", seat: p.seat, on: true }).catch(() => {});
    tellState(p);
  } else if (st === "disconnected" || st === "failed") {
    if (p.linked) invoke("room_do", { act: "linked", seat: p.seat, on: false }).catch(() => {});
    p.linked = false;
    if (!p.lostAt) p.lostAt = Date.now();
    if (st === "failed" && p.offerer && p.restarts < 3) offer(p, true);   // the later of the two asks for fresh paths
  }
  emit();
}

/** The pair's own words on its data channel: what each shows, and the owner's control (iOS Word). */
function wire(p, ch) {
  ch.onopen = () => tellState(p);
  ch.onmessage = (e) => {
    let w;
    try { w = JSON.parse(e.data); } catch { return; }
    const owner = E.live && p.seat === E.live.owner;
    if (w.c !== "st") mark(`channel ${w.c} from=${p.seat.slice(0, 4)}`);
    if (w.c === "st") {
      const showed = p.cameraOn || p.screen;
      p.muted = w.mu === 1; p.cameraOn = w.cam === 1; p.screen = w.scr === 1;
      // THE WATCHER SHOWS ME LARGE (iOS «big»): my picture to it goes whole
      if (p.wantsMe !== (w.big === 1)) { p.wantsMe = w.big === 1; mark(`pair ${p.seat.slice(0, 4)} wants me large=${p.wantsMe}`); tune(p); }
      if (!showed && (p.cameraOn || p.screen)) for (const ms of [4000, 9000]) setTimeout(() => markPicture(p, p.screen ? "screen" : "camera"), ms);
      emit();
    }
    else if (w.c === "mute" && owner) { setMuted(true); sayLine("The owner muted you"); }
    else if (w.c === "drop" && owner) { leave(false); sayLine("The owner removed you from the call"); }
    else if (w.c === "end" && owner) { leave(false); sayLine("The call has ended"); }
    else if (w.c === "bye") vanish(p.seat, false);
  };
}
function tellState(p) {
  if (p.channel?.readyState !== "open" || !E.live) return;
  p.channel.send(JSON.stringify({ c: "st", mu: E.muted || !stage(E.live.me) ? 1 : 0, cam: E.camera && !E.screen ? 1 : 0, scr: E.screen ? 1 : 0,
                                  big: E.focus === p.seat ? 1 : 0 }));
}
function command(p, c) { if (p.channel?.readyState === "open") p.channel.send(JSON.stringify({ c })); }

function drop(seat) {
  const p = E.pairs.get(seat);
  if (!p) return;
  E.pairs.delete(seat);
  clearTimeout(p.flush);
  p.channel?.close(); p.pc?.close();
  if (E.focus === seat) E.focus = null;
}
/** A PAIR BUILT ANEW BY THE LATER OF THE TWO (iOS rebirth): a higher generation, another connection. */
function rebirth(seat) {
  const p = E.pairs.get(seat);
  if (!p || !p.offerer || !E.live) return;
  E.genFloor[seat] = p.gen + 1;
  if (!E.unlinked[seat]) E.unlinked[seat] = p.lostAt || p.bornAt;
  drop(seat);
  const x = E.live.people.find((y) => y.seat === seat);
  if (x) pairUp(x);
}
/** A seat that fell silent without a word, or whose pair said bye: Rust takes it out (and the first in says so). */
function vanish(seat, tellGroup) {
  mark(`vanish ${seat.slice(0, 4)} tell=${tellGroup}`);
  drop(seat);
  invoke("room_do", { act: tellGroup ? "vanish" : "bye", seat }).catch(() => {});
}

/** THE BEAT (iOS beat, the pairs' part): an unanswered offer again, a fallen pair built anew, a seat silent three minutes gone. */
async function beat() {
  if (!E.live) return;
  const now = Date.now();
  for (const p of [...E.pairs.values()]) {
    if (p.offerer && !p.answered && p.lastOffer && now - p.offeredAt > 5000 && p.offers < 12) {
      p.offeredAt = now; p.offers += 1;
      send(p, "offer", { sdp: p.lastOffer });
    }
    const fell = p.lostAt ? now - p.lostAt > LOST_MS : !p.everLinked && now - p.bornAt > BIRTH_MS;
    if (fell) {
      if (now - (E.unlinked[p.seat] || p.bornAt) > GONE_MS) vanish(p.seat, true);
      else if (p.offerer) rebirth(p.seat);
    }
  }
  // a voice that came into the room while it is recorded joins the recording
  if (E.tape) E.pairs.forEach((p) => E.tape.feed(p.stream, p.seat + ":" + p.gen));
  // the voices measured: who speaks now
  for (const p of E.pairs.values()) {
    if (!p.pc) continue;
    try {
      const stats = await p.pc.getStats();
      let lv = 0;
      stats.forEach((r) => { if (r.type === "inbound-rtp" && r.kind === "audio") lv = Math.max(lv, r.audioLevel || 0); });
      p.level = lv;
      if (p === [...E.pairs.values()].find((x) => x.linked)) {
        let mine = 0;
        stats.forEach((r) => { if (r.type === "media-source" && r.kind === "audio") mine = Math.max(mine, r.audioLevel || 0); });
        E.level = mine;
      }
    } catch { /* a closed connection */ }
  }
  emit();
}

// ───────────────────────────── the person's hand ─────────────────────────────

export function setMuted(on) {
  E.muted = on;
  E.stream?.getAudioTracks().forEach((x) => { x.enabled = !on; });
  E.pairs.forEach(tellState);
  emit();
}
export async function setCamera(on) {
  if (!E.live || !stage(E.live.me)) return;
  if (on && !E.video) {
    try { E.video = await navigator.mediaDevices.getUserMedia({ video: { width: 640, height: 360, frameRate: 24 } }); }
    catch { sayLine("The camera is unavailable"); return; }
  }
  E.camera = on;
  if (!on) { E.video?.getTracks().forEach((x) => x.stop()); E.video = null; }
  E.pairs.forEach((p) => { dress(p); tellState(p); });
  emit();
}
/** MY SCREEN IN THE ROOM (iOS screenOn): Windows' own picker chooses it; it rides every pair's video line in the camera's place,
 *  the camera rests under it and comes back after; «scr» in the pair's state word tells each watcher to fit it whole. */
export async function setScreen(on) {
  if (!E.live || !stage(E.live.me) || on === E.screen) return;
  if (on) {
    let shot;
    try { shot = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 15 }, audio: false }); } catch { return; }   // nothing chosen
    const track = shot.getVideoTracks()[0];
    if (!track || !E.live) { shot.getTracks().forEach((x) => x.stop()); return; }
    track.contentHint = "detail";
    track.onended = () => setScreen(false);   // the system's own «stop sharing»
    E.screenTrack = track; E.screen = true;
  } else {
    if (E.screenTrack) { E.screenTrack.onended = null; E.screenTrack.stop(); }
    E.screenTrack = null; E.screen = false;
  }
  mark(`screen ${on ? "on" : "off"}`);
  E.pairs.forEach((p) => { dress(p); tellState(p); });
  emit();
}
/** THE ROOM RECORDED (iOS MTCallRecording, sendsToChat for a room: every participant sends their own): my voice and every voice
 *  of the room, as they come and go, mixed into an MP4 (AAC); the group is told first in iOS's words; at the stop or the room's end
 *  the recording goes to the group's chat as «Запись звонка». */
export async function setTape(on) {
  if (!E.live || on === !!E.tape) return;
  if (!on) { stopTape(); emit(); return; }
  try {
    const ctx = new AudioContext();
    const mix = ctx.createMediaStreamDestination();
    const fed = new Set();
    const feed = (stream, key) => {
      if (!stream?.getAudioTracks().length || fed.has(key)) return;
      fed.add(key);
      ctx.createMediaStreamSource(new MediaStream(stream.getAudioTracks())).connect(mix);
    };
    feed(E.stream, "me");
    E.pairs.forEach((p) => feed(p.stream, p.seat + ":" + p.gen));
    const type = "audio/mp4;codecs=mp4a.40.2";
    const recorder = new MediaRecorder(mix.stream, MediaRecorder.isTypeSupported(type) ? { mimeType: type } : {});
    const parts = [];
    recorder.ondataavailable = (e) => { if (e.data?.size) parts.push(e.data); };
    recorder.start(1000);
    E.tape = { ctx, feed, recorder, parts, at: Date.now(), chat: E.live.chat };
    mark("record start");
    invoke("chat_send", { chat: E.live.chat, text: t("This call is being recorded. The recording will be sent to this chat after the call."), qt: null, qm: null }).catch(() => {});
  } catch {
    mark("record refused");
  }
  emit();
}
function stopTape() {
  const tape = E.tape;
  if (!tape) return;
  E.tape = null;
  const secs = Math.round((Date.now() - tape.at) / 100) / 10;
  tape.recorder.onstop = () => {
    tape.ctx.close().catch(() => {});
    const blob = new Blob(tape.parts, { type: "audio/mp4" });
    mark(`record stop bytes=${blob.size} secs=${secs}`);
    if (!blob.size) return;
    sendFile(tape.chat, new File([blob], "call.m4a", { type: "audio/mp4" }), t("Call recording"), null, { k: "aud", du: secs }).catch(() => mark("record send refused"));
  };
  try { tape.recorder.stop(); } catch { /* already stopped */ }
}
/** The pairs let go after their last word left: the channel's «bye» is the proven one, and a connection closed at once drops it. */
function closeAfterWords() {
  const pairs = [...E.pairs.values()];
  E.pairs.clear();
  setTimeout(() => pairs.forEach((p) => { clearTimeout(p.flush); p.channel?.close(); p.pc?.close(); }), 500);
  closeAll();
}
export function leave(tellGroup = true) {
  if (!E.live) return;
  mark(`leave pairs=${E.pairs.size} open=${[...E.pairs.values()].filter((p) => p.channel?.readyState === "open").length}`);
  const ends = E.live.kind === "live" && E.live.owner === E.live.me;
  for (const p of E.pairs.values()) { command(p, ends ? "end" : "bye"); send(p, "bye"); }
  closeAfterWords();
  if (tellGroup) invoke("room_do", { act: "leave" }).catch(() => {});
  E.live = null;
  emit();
}
export function endForEveryone() {
  if (!E.live || E.live.owner !== E.live.me) return;
  for (const p of E.pairs.values()) command(p, "end");
  closeAfterWords();
  invoke("room_do", { act: "end" }).catch(() => {});
  E.live = null;
  emit();
}
export function ownerMute(seat) { const p = E.pairs.get(seat); if (p && E.live?.owner === E.live?.me) command(p, "mute"); }
export function ownerDrop(seat) {
  const p = E.pairs.get(seat);
  if (!p || E.live?.owner !== E.live?.me) return;
  command(p, "drop");
  invoke("room_do", { act: "drop", seat }).catch(() => {});
  setTimeout(() => drop(seat), 1000);
}
export function showRoom(on) { E.shown = on; emit(); }
/** A picture tapped is shown large (iOS focus): the one it belongs to is told, so its picture to me goes whole. */
export function setFocus(seat) {
  E.focus = E.focus === seat ? null : seat;
  E.pairs.forEach(tellState);
  emit();
}
const busyCall = () => typeof window.montanaCallBusy === "function" && window.montanaCallBusy();
export async function joinRoom(chat) {
  if (E.live?.chat === chat) return showRoom(true);
  if (busyCall()) return sayLine("Finish the current call first");
  if (E.live) leave();
  // a video chat is joined with the camera, as it was opened (iOS tapped -> join(video:))
  await invoke("room_join", { chat, video: !!E.rooms[chat]?.video }).catch((e) => sayLine(String(e)));
}
export async function openRoom(chat, kind, video, seats) {
  if (busyCall()) return sayLine("Finish the current call first");
  if (E.live && E.live.chat !== chat) leave();
  await invoke("room_open", { chat, kind, video, seats }).catch((e) => sayLine(String(e)));
  if (video && kind === "call") setCamera(true);
}
export function inviteSeats(seats) { invoke("room_do", { act: "invite", seats }).catch(() => {}); }

// ───────────────────────────── the screen ─────────────────────────────

const kindName = (kind, video) => t(kind === "live" ? "Live stream" : video ? "Video chat" : "Voice chat");

/** THE ROOM OVER ITS CHAT (iOS MTRoomBar): a group whose room lives shows it -- the way in, or back. */
export function RoomBar({ chat }) {
  const r = useRoom();
  const b = r.rooms[chat];
  if (!b) return null;
  const detail = b.mine ? t("Tap to return") : b.asker ? t("%@ invites you").replace("%@", b.asker)
    : b.kind === "live" ? t("%lld watching").replace("%lld", b.count) : t("%lld of %lld").replace("%lld", b.count).replace("%lld", CAPACITY);
  return (
    <button className="room-bar" onClick={() => (b.mine ? showRoom(true) : joinRoom(chat))} aria-label={`${kindName(b.kind, b.video)}: ${detail}`}>
      <span className="room-bar-dot"><Glyph name={b.video ? "video" : "calls"} size={16} color="#fff" /></span>
      <span className="room-bar-words"><b>{kindName(b.kind, b.video)}</b><span>{detail}</span></span>
      <Glyph name="chevronRight" size={14} color="var(--gray)" />
    </button>
  );
}

/** A GROUP'S LIVING ROOM IN THE CHATS' LIST (iOS MTRoomRowMark, MTGroupRoom.swift 2658-2672): a small green mark beside the group's name --
 *  dot.radiowaves for a live stream, video.fill for a video chat, phone.fill for a voice chat, 12 semibold; the row stays one button. */
export function RoomRowMark({ chat }) {
  const r = useRoom();
  const b = r.rooms[chat];
  if (!b) return null;
  return (
    <span className="room-row-mark" role="img" aria-label={kindName(b.kind, b.video)}>
      <Glyph name={b.kind === "live" ? "antenna" : b.video ? "video" : "phone"} size={13} color="var(--green)" />
    </span>
  );
}

/** THE PHONE MARK OF A GROUP (iOS MTRoomMark): a living room is joined at once; else the kind, then whom to invite. */
export function RoomMark({ chat, kinds, onAsk }) {
  const r = useRoom();
  const [menu, setMenu] = useState(false);
  const living = r.rooms[chat];
  if (!living && !kinds?.length) return null;
  return (
    <>
      <button className={"glass-mark call-mark" + (living ? " ringed" : "")} aria-label={t(living ? "Join the Call" : "Call")}
              onClick={() => (living ? (living.mine ? showRoom(true) : joinRoom(chat)) : setMenu(!menu))}>
        <Glyph name="calls" size={20} color="rgb(204,204,204)" />
      </button>
      {menu && (
        <div className="menu-shade" onClick={() => setMenu(false)}>
          <div className="letter-menu call-menu" onClick={(e) => e.stopPropagation()} role="menu">
            <div className="menu-rows">
              {kinds.includes("call") && <button className="menu-row" role="menuitem" onClick={() => { setMenu(false); onAsk("call", false); }}><span>{t("Voice Chat")}</span><Glyph name="calls" size={18} /></button>}
              {kinds.includes("call") && <button className="menu-row" role="menuitem" onClick={() => { setMenu(false); onAsk("call", true); }}><span>{t("Video Chat")}</span><Glyph name="video" size={18} /></button>}
              {kinds.includes("live") && <button className="menu-row" role="menuitem" onClick={() => { setMenu(false); onAsk("live", true); }}><span>{t("Live Stream")}</span><Glyph name="video" size={18} /></button>}
            </div>
          </div>
        </div>
      )}
    </>
  );
}

/** WHOM TO INVITE (iOS MTRoomInviteSheet): everyone, or each by a tick; the room opens with them, or they are invited into it. */
export function RoomInvite({ chat, kind, video, opening, onClose }) {
  const [people, setPeople] = useState(null);
  const [chosen, setChosen] = useState(new Set());
  useEffect(() => { invoke("room_invitable", { chat }).then(setPeople).catch(() => setPeople([])); }, [chat]);
  const all = (people || []).map(([s]) => s);
  const flip = (s) => setChosen((c) => { const n = new Set(c); if (n.has(s)) n.delete(s); else n.add(s); return n; });
  const go = () => {
    onClose();
    if (opening) openRoom(chat, kind, video, [...chosen]);
    else inviteSeats([...chosen]);
  };
  return (
    <div className="menu-shade" onClick={onClose}>
      <div className="room-invite" onClick={(e) => e.stopPropagation()} role="dialog" aria-label={t(kind === "live" ? "Live Stream" : video ? "Video Chat" : "Voice Chat")}>
        <header className="room-invite-head">
          <button className="glass-mark" onClick={onClose} aria-label={t("Cancel")}><Glyph name="close" size={16} color="rgb(204,204,204)" /></button>
          <b>{t(kind === "live" ? "Live Stream" : video ? "Video Chat" : "Voice Chat")}</b>
          <button className="glass-mark" onClick={go} aria-label={t("Invite")}><Glyph name="check" size={16} color="rgb(204,204,204)" /></button>
        </header>
        {people?.length > 0 && (
          <button className="room-person" aria-pressed={chosen.size === all.length} onClick={() => setChosen(chosen.size === all.length ? new Set() : new Set(all))}>
            <span className="room-face">∗</span><span className="grow">{t("Everyone")}</span><span className={"tick" + (chosen.size === all.length ? " on" : "")} />
          </button>
        )}
        {(people || []).map(([seat, name]) => (
          <button key={seat} className="room-person" aria-pressed={chosen.has(seat)} aria-label={`${t("Invite")}: ${name}`} onClick={() => flip(seat)}>
            <span className="room-face">{(name || "?").slice(0, 1).toUpperCase()}</span><span className="grow">{name}</span>
            <span className={"tick" + (chosen.has(seat) ? " on" : "")} />
          </button>
        ))}
        <div className="room-invite-foot">{t("The people chosen get a way into the call. Nobody's phone rings.")}</div>
      </div>
    </div>
  );
}

/** THE ROOM'S SCREEN (iOS MTRoomScreen) and its voices; minimized, a pill that brings it back. */
export default function RoomLayer() {
  const r = useRoom();
  const [inviting, setInviting] = useState(false);
  const [confirmEnd, setConfirmEnd] = useState(false);
  const [menuFor, setMenuFor] = useState(null);
  useEffect(() => {
    const stops = [];
    let gone = false;
    const on = (name, f) => listen(name, (e) => f(e.payload)).then((u) => { if (gone) u(); else stops.push(u); });
    on("montana://room", (v) => state(v));
    on("montana://room-signal", (w) => signal(w));
    on("montana://room-say", (v) => sayLine(v.say));
    invoke("room_state").then(state).catch(() => {});
    const tick = setInterval(beat, 1000);
    const said = (e) => sayLine(e.detail);
    window.addEventListener("montana-room-say", said);
    return () => { gone = true; stops.forEach((u) => u()); clearInterval(tick); window.removeEventListener("montana-room-say", said); };
  }, []);
  const audios = [...r.pairs.values()].filter((p) => p.stream).map((p) => (
    <audio key={p.seat + p.gen} autoPlay ref={(el) => { if (el && el.srcObject !== p.stream) el.srcObject = p.stream; }} />
  ));
  if (!r.live) return r.note ? <div className="room-note" role="status">{r.note}</div> : null;
  const live = r.live, amOwner = live.owner === live.me, speaks = stage(live.me);
  if (!r.shown) {
    return (
      <>
        {audios}
        <button className="room-pill" onClick={() => showRoom(true)} aria-label={t("Return to the call")}>
          <span className="seen-dot live" />{live.title} · {kindName(live.kind, live.video)} · {live.people.length}
        </button>
      </>
    );
  }
  const status = (x) => {
    if (x.me) return t("this is you");
    const p = r.pairs.get(x.seat);
    if (!p?.linked) return t("connecting");
    return p.level > SPEAKING && !p.muted ? t("speaking") : t("listening");
  };
  const count = live.kind === "live" ? t("%lld watching").replace("%lld", live.people.length) : `${live.people.length} / ${CAPACITY}`;
  return (
    <div className="call-screen room-screen" role="dialog" aria-label={`${kindName(live.kind, live.video)}: ${live.title}`}>
      {audios}
      <header className="room-head">
        <div className="room-title"><b>{live.title}</b><span>{kindName(live.kind, live.video)} · {count}</span></div>
        <button className="glass-mark" onClick={() => showRoom(false)} aria-label={t("Minimize")}><Glyph name="close" size={16} color="#fff" /></button>
      </header>
      <div className="room-tiles">
        {live.people.map((x) => {
          const p = r.pairs.get(x.seat);
          const muted = x.me ? r.muted || !speaks : p ? p.muted : !stage(x.seat);
          const talking = x.me ? !r.muted && speaks && r.level > SPEAKING : p?.linked && p.level > SPEAKING && !p.muted;
          return (
            <div key={x.seat} className={"room-tile" + (talking ? " speaking" : "") + (r.focus === x.seat ? " big" : "")} role="group" aria-label={`${x.name}, ${status(x)}${muted ? ", " + t("Mute") : ""}`}>
              {!x.me && p?.stream && (p.cameraOn || p.screen) ? (
                <div className={"room-pic" + (p.screen ? " screen" : "")} role="button" tabIndex={0} aria-pressed={r.focus === x.seat}
                     aria-label={`${x.name}: ${t(p.screen ? "Screen" : "Video")}`} onClick={() => setFocus(x.seat)}
                     onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") setFocus(x.seat); }}>
                  <video autoPlay playsInline muted ref={(el) => { p.el = el; if (el && el.srcObject !== p.stream) el.srcObject = p.stream; }} />
                </div>
              ) : x.me && r.camera && !r.screen && r.video ? (
                <div className="room-pic mine"><video autoPlay playsInline muted ref={(el) => { if (el && el.srcObject !== r.video) el.srcObject = r.video; }} /></div>
              ) : null}
              <span className="room-face big">{(x.name || "?").slice(0, 1).toUpperCase()}</span>
              <span className="room-tile-name">{x.name}{x.owner ? " ★" : ""}</span>
              <span className="room-tile-status">{status(x)}</span>
              {muted && <Glyph name="mic" size={14} color="rgb(255,120,120)" />}
              {amOwner && !x.me && (
                <button className="room-tile-more" onClick={() => setMenuFor(menuFor === x.seat ? null : x.seat)} aria-label={`${t("More")}: ${x.name}`}>⋯</button>
              )}
              {menuFor === x.seat && (
                <div className="room-tile-menu" role="menu">
                  <button role="menuitem" onClick={() => { setMenuFor(null); ownerMute(x.seat); }}>{t("Mute")}</button>
                  <button role="menuitem" className="red" onClick={() => { setMenuFor(null); ownerDrop(x.seat); }}>{t("Remove from Call")}</button>
                </div>
              )}
            </div>
          );
        })}
        {live.ringing.map((x) => (
          <div key={"ring-" + x.seat} className="room-tile ringing" role="group" aria-label={`${x.name}, ${t("calling")}`}>
            <span className="room-face big">{(x.name || "?").slice(0, 1).toUpperCase()}</span>
            <span className="room-tile-name">{x.name}</span><span className="room-tile-status">{t("calling")}</span>
          </div>
        ))}
        {live.kind === "call" && live.people.length < CAPACITY && (
          <button className="room-tile invite" onClick={() => setInviting(true)} aria-label={t("Invite Member")}><Glyph name="plus" size={20} color="#fff" /><span>{t("Invite Member")}</span></button>
        )}
      </div>
      {r.note && <div className="room-note inline" role="status">{r.note}</div>}
      {r.tape && <div className="call-taping room" role="status"><span className="rec-dot" />{t("Recording")}</div>}
      <div className="call-keys">
        {speaks && (
          <button className={"call-key" + (r.muted ? " on" : "")} onClick={() => setMuted(!r.muted)} aria-label={t("Microphone")} aria-pressed={r.muted}>
            <Glyph name="mic" size={26} color="#fff" /><span>{t("Microphone")}</span>
          </button>
        )}
        {speaks && live.kind === "call" && (
          <button className={"call-key" + (r.camera ? " on" : "")} onClick={() => setCamera(!r.camera)} aria-label={t("Video")} aria-pressed={r.camera}>
            <Glyph name="video" size={26} color="#fff" /><span>{t("Video")}</span>
          </button>
        )}
        {speaks && (
          <button className={"call-key" + (r.screen ? " on" : "")} onClick={() => setScreen(!r.screen)} aria-label={t(r.screen ? "Screen" : "Share Screen")} aria-pressed={r.screen}>
            <Glyph name="antenna" size={26} color="#fff" /><span>{t("Screen")}</span>
          </button>
        )}
        {speaks && (
          <button className={"call-key" + (r.tape ? " on" : "")} onClick={() => setTape(!r.tape)} aria-label={t(r.tape ? "Stop recording" : "Record")} aria-pressed={!!r.tape}>
            <Glyph name="circle" size={26} color={r.tape ? "#ff453a" : "#fff"} /><span>{t(r.tape ? "Stop recording" : "Record")}</span>
          </button>
        )}
        {amOwner && (
          <button className="call-key" onClick={() => setConfirmEnd(true)} aria-label={t("End for Everyone")}>
            <Glyph name="calls" size={26} color="#fff" /><span>{t("End for Everyone")}</span>
          </button>
        )}
        <button className="call-key red leave" onClick={() => leave()} aria-label={t("Leave")}><Glyph name="close" size={26} color="#fff" /><span>{t("Leave")}</span></button>
      </div>
      {confirmEnd && (
        <div className="menu-shade" onClick={() => setConfirmEnd(false)}>
          <div className="letter-menu" onClick={(e) => e.stopPropagation()} role="menu">
            <div className="menu-rows">
              <button className="menu-row red" role="menuitem" onClick={() => { setConfirmEnd(false); endForEveryone(); }}><span>{t("End for Everyone")}</span></button>
              <button className="menu-row" role="menuitem" onClick={() => setConfirmEnd(false)}><span>{t("Cancel")}</span></button>
            </div>
          </div>
        </div>
      )}
      {inviting && <RoomInvite chat={live.chat} kind={live.kind} video={live.video} opening={false} onClose={() => setInviting(false)} />}
    </div>
  );
}
