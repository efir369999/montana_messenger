import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { BIG, urlOf } from "./Media.jsx";
import { chatName } from "./Chats.jsx";

/** THE ONE PLAYER OF THE APP (iOS VoicePlayer.shared): music outlives the page it was started on, its queue walks on by itself,
 *  and the window's own media keys and Windows' media flyout drive it (the lock screen's buttons on iOS). Voice and music are two
 *  things (iOS, the author's word 10.09): a voice never enters the music's queue and has its own speed (1 / 1.5 / 2) while music
 *  always plays at one; a voice started over a track sets the track aside, paused with its place, and the track comes back to the
 *  bar when the voice ends or is closed (iOS park / unpark, 26.09). One sound plays at a time. A track is
 *  { file, title, mid, ext, big, lent, chat } -- file names it in the queue: a letter's mid, or a lent folder's track id. */
const music = new Audio(), voice = new Audio();
const S = {
  file: null, voice: false, title: "", sender: "", chat: "", mid: "", paused: false, duration: 0,
  queue: [], index: -1, voices: [], repeat: "off", shuffle: false, parked: null, ticket: 0, source: "all", unfold: false,
};
let rate = Number(localStorage.getItem("voiceRate")) || 1;
const faces = new Set();
const mark = (line) => invoke("trace", { line }).catch(() => {});
const sound = () => (S.voice ? voice : music);

/** THE PLAYER'S FACE (iOS VoicePlayer.Face): what a row or the bar draws of the player -- which file plays, whether it rests, its
 *  length, the voice's speed, the queue's place -- told when one of them moves, never at the clock's tick (useClock is the clock). */
export function face() {
  const track = !S.voice && S.index >= 0 ? S.queue[S.index] : null;
  return { file: S.file, voice: S.voice, title: S.title, sender: S.sender, chat: S.chat, mid: S.mid, paused: S.paused, duration: S.duration,
           index: S.index, length: S.queue.length, track, rate, repeat: S.repeat, shuffle: S.shuffle, source: S.source, unfold: S.unfold };
}
function told() {
  const f = face();
  for (const l of faces) l(f);
  session();
}
export function usePlayer() {
  const [f, setF] = useState(face);
  useEffect(() => { faces.add(setF); setF(face()); return () => faces.delete(setF); }, []);
  return f;
}
/** The clock of what plays, for the one plate that shows it (iOS MTAudioLive): the place 0…1 and the seconds, four times a second. */
export function useClock(on = true) {
  const [c, setC] = useState({ at: 0, of: 0 });
  useEffect(() => {
    if (!on) return undefined;
    const tick = () => { const s = sound(); setC({ at: s.currentTime || 0, of: Number.isFinite(s.duration) ? s.duration : 0 }); };
    tick();
    const t = setInterval(tick, 250);
    return () => clearInterval(t);
  }, [on]);
  return c;
}
/** WHAT A TRACK CARRIES ITSELF (iOS MTTrackMeta): its tag's name, its artist, its length, its cover -- read once per file when a row
 *  or the player asks, kept for the session; the rows are drawn again when a reading lands. */
const metas = new Map(), asking = new Set(), metaHeard = new Set();
export function metaOf(item) {
  if (!item?.file) return null;
  if (metas.has(item.file)) return metas.get(item.file);
  if (!asking.has(item.file)) {
    asking.add(item.file);
    invoke("track_meta", { file: item.file, mid: item.mid || null, lent: !!item.lent, id: item.wall?.id ?? null, index: item.wall?.index ?? null,
                           ext: item.ext || null })
      .then((m) => { metas.set(item.file, m); if (item.file === S.file) session(); for (const l of metaHeard) l(); })
      .catch(() => metas.set(item.file, null))
      .finally(() => asking.delete(item.file));
  }
  return null;
}
export function useMeta(item) {
  const [, turn] = useState(0);
  useEffect(() => { const l = () => turn((n) => n + 1); metaHeard.add(l); return () => metaHeard.delete(l); }, []);
  return metaOf(item);
}
/** The track's name as the list names it: its tag's, else its file's (the row and the bar say one name). */
export const nameOf = (item) => metas.get(item?.file)?.title || item?.title || "";

/** A music file by its name (iOS mtIsAudioName). */
export const isMusicName = (name) => ["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "caf"].includes((String(name).split(".").pop() || "").toLowerCase());
/** A track's name as the list says it: its file's, its kind left out (iOS deletingPathExtension). */
export const stem = (name) => String(name || "").replace(/\.[^./\\]+$/, "");

/** THE TRACK'S PLACE ON THE MUSIC PAGE (iOS MTMusicFocus): the bar's name asks the page for it -- the page, when it stands, brings
 *  the row to the middle; a page opened for it takes the ask at its first look. */
let placeAsked = null;
export function askPlace(file) {
  placeAsked = file;
  window.dispatchEvent(new CustomEvent("montana-music-place", { detail: file }));
}
export function takePlace() { const f = placeAsked; placeAsked = null; return f; }

/** WHETHER THE MINI STANDS UNFOLDED (iOS MTPlayerUnfold): one fact for the bar of every page, so the bar on the next page stands as
 *  the person left it. */
export function setUnfold(on) {
  if (S.unfold === on) return;
  S.unfold = on;
  mark(on ? "music mini unfolds" : "music mini folds");
  told();
}

/** The bar stands while the player holds anything -- a track or a voice (iOS MontanaPlayerBar.standing). */
export const standing = () => S.file != null;

/** A call holds the sound (iOS MontanaAudioSession.refusedUnderCall): under a call nothing starts. */
const underCall = () => !!window.montanaCallBusy?.();

async function load(el, item, ticket) {
  const url = await urlOf(item).catch(() => null);
  if (!url || ticket !== S.ticket) return false;
  el.src = url;
  el.playbackRate = el === voice ? rate : 1;
  return true;
}

/** A TRACK OF THE QUEUE (iOS play(index:)): the list it was started from is the queue, the next one is the row below. */
export async function playQueue(queue, i) {
  S.queue = queue;
  return play(i);
}
export async function play(i) {
  const t = S.queue[i];
  if (!t) return;
  if (!S.voice && S.file === t.file) {   // the same track asked again: from its start (iOS music_again)
    S.index = i;
    music.currentTime = 0;
    if (S.paused) resume(); else told();
    return;
  }
  if (underCall()) { mark("music refused -- a call holds the sound"); return; }
  if (S.parked?.file === t.file && S.voice) { voice.pause(); voice.removeAttribute("src"); S.voice = false; return unpark(true); }
  dropParked();
  if (S.voice) { voice.pause(); voice.removeAttribute("src"); S.voice = false; }
  const ticket = ++S.ticket;
  S.index = i; S.file = t.file; S.title = t.title; S.mid = t.mid || ""; S.chat = t.chat || ""; S.paused = false; S.duration = 0;
  told();
  if (!(await load(music, t, ticket))) { if (ticket === S.ticket) { mark("music play_refused"); release(); } return; }
  music.currentTime = 0;
  const road = t.wall ? "wall" : t.lent ? "lent" : t.big ? "file" : "blob";   // which road brought it: the wall, a lent folder, the file road
  music.play().then(() => mark(`music_play i=${i + 1} n=${S.queue.length} kind=${(t.ext || "").toLowerCase()} road=${road} shuffle=${S.shuffle ? 1 : 0} repeat=${S.repeat}`))
    .catch(() => { mark("music play_refused"); release(); });
}

/** A VOICE WITH THE CHAT'S VOICES BEHIND IT (iOS playVoice): the one asked plays, auto-next walks the chat's voices forward. */
export async function playVoice(item, voices, chat, sender, at = null) {
  if (S.voice && S.file === item.file) return toggle();
  S.pendingAt = at;   // the finger's place on the wave: the voice starts there (iOS pendingPos)
  if (underCall()) { mark("voice refused -- a call holds the sound"); return; }
  park();
  const ticket = ++S.ticket;
  S.voices = voices; S.voice = true; S.file = item.file; S.mid = item.mid || item.file; S.chat = chat; S.sender = sender || item.sender || "";
  S.title = S.sender; S.paused = false; S.duration = 0;
  told();
  mark(`voice_play queue=${voices.length} at=${voices.findIndex((v) => v.file === item.file)}`);
  if (!(await load(voice, item, ticket))) { if (ticket === S.ticket) stop(); return; }
  voice.play().catch(() => { mark("voice play_refused"); stop(); });
}

export function toggle() { if (S.paused) resume(); else pause(); }
export function pause() {
  if (!S.file) return;
  S.ticket++;
  sound().pause();
  S.paused = true;
  told();
}
export function resume() {
  if (!S.file) return;
  if (underCall()) { mark("music refused -- a call holds the sound"); return; }
  sound().play().then(() => { S.paused = false; told(); }).catch(() => {});
}
export function seek(p) {
  const s = sound();
  if (!S.file || !Number.isFinite(s.duration) || s.duration <= 0) return;
  s.currentTime = Math.max(0, Math.min(s.duration - 0.2, s.duration * p));
  mark(`seek ${S.voice ? "voice" : "music"} to=${Math.round(s.currentTime)}s`);
}
/** The close (iOS stop): what plays stands down; a voice over a track gives the bar back to the track, paused where it stood. */
export function stop() {
  release();
  unpark();
}
function release() {
  S.ticket++;
  const s = sound();
  s.pause(); s.removeAttribute("src"); s.load();
  S.file = null; S.paused = false; S.duration = 0; S.voice = false; S.sender = ""; S.mid = ""; S.chat = "";
  if (!S.parked) S.index = -1;
  told();
}
function park() {
  if (S.voice || !S.file || S.index < 0) return;
  music.pause();
  S.parked = { file: S.file, index: S.index, title: S.title, mid: S.mid, chat: S.chat };
  mark(`music_park aside at=${Math.round(music.currentTime)}s`);
}
function unpark(go = false) {
  const pk = S.parked;
  if (!pk || (S.file && !go)) return;
  S.parked = null;
  const i = S.queue.findIndex((q) => q.file === pk.file);
  if (i < 0) { music.removeAttribute("src"); mark("music_park let go -- the queue no longer holds it"); return; }
  Object.assign(S, { voice: false, index: i, file: pk.file, title: pk.title, mid: pk.mid, chat: pk.chat, paused: !go, duration: music.duration || 0 });
  mark(`music_park back at=${Math.round(music.currentTime)}s ${go ? "on" : "paused"}`);
  if (go) music.play().catch(() => {});
  told();
}
function dropParked() {
  if (!S.parked) return;
  S.parked = null;
  music.pause();
  mark("music_park let go -- another track");
}
/** THE LIBRARY (iOS MontanaMusicLibrary.build): every letter's audio file on this computer and the lent folders' tracks, in order of
 *  appearance across every chat -- a lent folder's tracks at the moment it was lent, in its own order, a letter first on a tie --
 *  one track once: the same song sent twice or lying in a folder as well is one row and one place in the queue (the name without
 *  its kind and the size). A voice is no track (iOS: voice and music are two things). */
export function library(files, lent) {
  const letters = files.filter((f) => f.file && f.m.k === "doc" && (isMusicName(f.m.n || "") || isMusicName(`x.${f.m.e || ""}`)))
    .map((f) => ({ file: f.mid, mid: f.mid, ext: f.m.e, big: f.m.sz > BIG, title: stem(f.m.n || ""), chat: f.chat, chatTitle: chatName(f.name),
                   at: f.at || 0, size: f.m.sz || 0 }))
    .sort((a, b) => a.at - b.at);
  const folders = lent.map((x) => ({ file: x.id, lent: true, ext: x.e, title: stem(x.title), at: x.at || 0, size: x.sz || 0 }));
  const merged = [];
  for (let i = 0, j = 0; i < letters.length || j < folders.length;) {
    if (j === folders.length || (i < letters.length && letters[i].at <= folders[j].at)) merged.push(letters[i++]); else merged.push(folders[j++]);
  }
  const files_ = new Set(), seen = new Set();
  return merged.filter((x) => {
    const key = `${x.title.toLowerCase()}#${x.size}`;
    if (files_.has(x.file) || seen.has(key)) return false;
    files_.add(x.file); seen.add(key);
    return true;
  });
}
const readLibrary = async () => {
  const [files, st] = await Promise.all([invoke("media_list").catch(() => []), invoke("music_state").catch(() => null)]);
  return library(files || [], st?.tracks || []);
};
/** THE WALLS' TRACKS (iOS MTBoardPlaylist): the feed's posts and my wall's, each post's tracks in its order, one file once. */
export function wallTracks(items) {
  const once = new Set(), out = [];
  for (const { post, wall } of items) {
    (post.media || []).forEach((x, i) => {
      if (x.kind !== "aud") return;
      const file = `wall:${wall || ""}/${post.id}/${i}`;
      if (once.has(file)) return;
      once.add(file);
      out.push({ file, wall: { wall, id: post.id, index: i }, ext: x.ext, title: stem(x.name) || x.name || "", chatTitle: post.byName || "", at: post.at || 0 });
    });
  }
  return out;
}
const readWalls = async () => {
  const [feed, mine] = await Promise.all([invoke("wall_feed").catch(() => []), invoke("wall_state", { wall: null }).catch(() => null)]);
  return wallTracks([...(feed || []).map((it) => ({ post: it.post, wall: it.wall })), ...(mine?.posts || []).map((p) => ({ post: p, wall: null }))]);
};
/** Where a track lies (iOS MTTrackSource.of): a lent folder, a wall, or its chat. */
const sourceOf = (x) => (x.lent ? "folders" : x.wall ? "walls" : `chat:${x.chat}`);
const holds = (s, x) => s === "all" || (s === "chats" ? sourceOf(x).startsWith("chat:") : sourceOf(x) === s);
/** A SOURCE CHOSEN, WHAT PLAYS IS THAT SOURCE (iOS MTTrackSource.listen): its tracks become the queue, and the track that plays keeps
 *  playing when the source holds it, else the source's first plays; a source with no track changes nothing. */
export async function listen(s) {
  const list = s === "walls" ? await readWalls() : (await readLibrary()).filter((x) => holds(s, x));
  if (!list.length) return;
  S.source = s;
  const playing = !S.voice ? S.file : null;
  S.queue = list;
  const i = playing ? list.findIndex((q) => q.file === playing) : -1;
  mark(`music_source listen n=${list.length}`);
  if (i >= 0) { S.index = i; told(); } else play(0);
}
/** The chats the library's letters came from, each once, in the library's order: the filter's one-chat choice. */
export async function sourceChats() {
  const once = new Set();
  return (await readLibrary()).filter((x) => !x.lent && !once.has(x.chat) && once.add(x.chat)).map((x) => ({ id: x.chat, title: x.chatTitle }));
}
/** The queue as it stands, and where it plays from (iOS MTQueuePage.from): one chat's name, the walls, the folders, the chats, else all. */
export const queue = () => [...S.queue];
export function sourceName() {
  const kinds = new Set(S.queue.map(sourceOf));
  if (kinds.size === 1) {
    const k = [...kinds][0];
    if (k === "walls") return "Walls";
    if (k === "folders") return "Folders";
    return S.queue[0]?.chatTitle || "";
  }
  return [...kinds].every((k) => k.startsWith("chat:")) ? "Chats" : "All";
}
/** A track out of the queue (iOS dropFromQueue): the turn goes on from the place it stood; the last one out ends the play. */
export function dropFromQueue(file) {
  const i = S.queue.findIndex((q) => q.file === file);
  if (i < 0) return;
  const was = i === S.index;
  S.queue.splice(i, 1);
  mark(`music_queue out i=${i + 1} n=${S.queue.length} playing=${was ? 1 : 0}`);
  if (i < S.index) { S.index -= 1; return told(); }
  if (!was) return told();
  if (!S.queue.length) { S.index = -1; return stop(); }
  S.index = i - 1;
  next();
}
/** The order turned over (iOS reverseQueue): the track that plays keeps playing at its new place. */
export function reverseQueue() {
  if (S.queue.length < 2) return;
  const playing = S.index >= 0 ? S.queue[S.index].file : null;
  S.queue.reverse();
  if (playing) S.index = S.queue.findIndex((q) => q.file === playing);
  mark(`music_queue reversed n=${S.queue.length} playing_at=${S.index + 1}`);
  told();
}
/** The player's own share of the sound (iOS: the system's volume; a page cannot move Windows' own), kept across launches. */
export const volume = () => music.volume;
export function setVolume(x) {
  music.volume = voice.volume = Math.max(0, Math.min(1, x));
  try { localStorage.setItem("musicVolume", String(music.volume)); } catch { /* this run */ }
}
try { const v = Number(localStorage.getItem("musicVolume")); if (localStorage.getItem("musicVolume") != null && v >= 0 && v <= 1) music.volume = voice.volume = v; } catch { /* the default */ }
/** THE TRACK HANDED ON UNDER THE NAME THE PAGE SHOWS (iOS MontanaPlayerBar.share): a lent track whose bytes are not here is not handed. */
export async function share() {
  const t = !S.voice && S.index >= 0 ? S.queue[S.index] : null;
  if (!t) return false;
  mark("music player share named=1");
  return invoke("share_file", { mid: t.lent || t.wall ? null : t.mid, lent: t.lent ? t.file : null, id: t.wall?.id ?? null, index: t.wall?.index ?? null,
                                title: t.title, ext: t.ext || "mp3" }).catch(() => false);
}

/** A call is born: what plays stands down (iOS yieldToCall). */
export function yieldToCall() {
  if (!S.file || S.paused) return;
  pause();
  mark(`music_yield voice=${S.voice ? 1 : 0} -- the call took the sound`);
}

const nextIndex = () => {
  if (!S.queue.length) return null;
  if (S.shuffle) { const rest = S.queue.map((_, i) => i).filter((i) => i !== S.index); return rest.length ? rest[Math.floor(Math.random() * rest.length)] : null; }
  return S.index + 1 < S.queue.length ? S.index + 1 : null;
};
/** The track after (iOS next): the queue's own turn, the first again past the last. */
export function next() {
  const nx = nextIndex();
  if (nx != null) play(nx); else if (S.queue.length) play(0);
}
/** The track before (iOS prev): past three seconds the same track from its start. */
export function prev() {
  if (music.currentTime > 3) { music.currentTime = 0; return; }
  if (S.index > 0) play(S.index - 1); else music.currentTime = 0;
}
/** THE REPEAT'S ROUND (iOS turnRepeat): off, the track, the playlist, off. */
export function turnRepeat() {
  S.repeat = S.repeat === "off" ? "track" : S.repeat === "track" ? "all" : "off";
  mark(`music repeat ${S.repeat === "all" ? "playlist" : S.repeat}`);
  told();
}
export function turnShuffle() { S.shuffle = !S.shuffle; told(); }
/** The voice's speed, one tap around: 1 → 1.5 → 2 → 1 (iOS voiceRate), kept across launches. */
export function turnRate() {
  rate = rate >= 2 ? 1 : rate >= 1.5 ? 2 : 1.5;
  try { localStorage.setItem("voiceRate", String(rate)); } catch { /* the speed stays for this run */ }
  voice.playbackRate = rate;
  mark(`voice rate ${rate}`);
  told();
}

music.onended = () => {   // iOS finished(): the track again, the next, the playlist from its first, else the bar stands down
  if (S.voice) return;
  if (S.repeat === "track") { music.currentTime = 0; music.play().catch(() => {}); return; }
  const nx = nextIndex();
  if (nx != null) return play(nx);
  if (S.repeat === "all" && S.queue.length) return play(0);
  stop();
};
voice.onended = () => {   // the chat's next voice, else the voice ends and the track aside comes back
  const i = S.voices.findIndex((v) => v.file === S.file);
  const n = i >= 0 ? S.voices[i + 1] : null;
  if (n) { mark(`voice_next i=${i + 1} n=${S.voices.length}`); S.file = null; return playVoice(n, S.voices, S.chat, n.sender); }
  mark(`voice_end queue=${S.voices.length}`);
  stop();
};
for (const el of [music, voice]) {
  el.onloadedmetadata = () => {
    if (el === voice && S.pendingAt != null && Number.isFinite(el.duration)) { el.currentTime = el.duration * S.pendingAt; S.pendingAt = null; }
    if (el === sound() && Number.isFinite(el.duration)) { S.duration = el.duration; told(); }
  };
  el.onpause = () => { if (el === sound() && S.file && !S.paused && !el.ended && el.src) { S.paused = true; told(); } };
  el.onplay = () => { if (el === sound() && S.paused) { S.paused = false; told(); } };
}

/** WINDOWS' MEDIA FLYOUT AND KEYS ARE THE MUSIC'S, NOT A VOICE'S (iOS armRemote / pushNowPlaying): the track's name, the play, the
 *  pause, the track before and after, the place. */
function session() {
  const ms = navigator.mediaSession;
  if (!ms) return;
  const track = !S.voice && S.file;
  const m = track ? metas.get(S.file) : null;
  try {
    ms.metadata = track ? new MediaMetadata({ title: m?.title || S.title, artist: m?.artist || "Montana", artwork: m?.cover ? [{ src: m.cover }] : [] }) : null;
    ms.playbackState = !S.file ? "none" : S.paused ? "paused" : "playing";
    ms.setActionHandler("play", track ? () => resume() : null);
    ms.setActionHandler("pause", track ? () => pause() : null);
    ms.setActionHandler("previoustrack", track ? () => prev() : null);
    ms.setActionHandler("nexttrack", track ? () => next() : null);
    ms.setActionHandler("seekto", track ? (d) => { if (music.duration > 0) music.currentTime = d.seekTime; } : null);
  } catch { /* a handler this WebView does not know */ }
}
