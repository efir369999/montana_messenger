//! THE COMPUTER HOLDS ITS NODES (iOS 2304 MontanaNodes.open 260-323, MontanaDirect startKeepalive 622, maybeReady 1112, onChannelUp
//! 1142, sendUnderTag 1292, handleOverlayFrame 1318; Android Channels): a node is a meeting and transit point, and the link to it is
//! held while the app lives. Every door of the network's list is knocked unless it stands; a door that did not stand waits its step
//! -- two seconds, doubled with a spread at every knock, under fifteen, and up to ten minutes once it refused. One machine, one
//! channel: of the doors standing to one machine the fastest stays. Every eight seconds each standing channel is kept warm, and
//! a machine that has not named its owner is given ours again, ten times at most. A cell that arrives is acknowledged and opened
//! when it is mine and carried on when it is not; a letter is laid before the nodes under its pipe's tag beside the box's road,
//! and the receiving side drops the second copy by its mid.
//!
//! On Windows the doors behind a delivery network («wss://») and the bare doors off 443 are dialled; the bare door on 443 wants
//! the node's ALPN, which WinHTTP does not name. This computer does not answer on the direct port yet (a listener asks the
//! person through Windows' firewall).

use crate::channel::{self, net, Channel, Door, Heard, Ident, OverlayFrame};
use crate::wire;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

const STEP_MIN: f64 = 2.0;
const STEP_MAX: f64 = 15.0;
const STEP_DEAD_MAX: f64 = 600.0;
/// iOS frameMemory: the frames seen and the frames of mine remembered, a sliding window.
const FRAME_MEMORY: usize = 8192;
/// iOS repairUnnamedOwners: a machine that never named its owner is given ours again, ten times at most.
const OWNER_ASKS: u32 = 10;

type Land = dyn Fn(&str, &[u8]) + Send + Sync;

/// What the holder asks of the person seated, and where a letter off a channel lands.
pub struct Hooks {
    /// the person's pipes: (reference, secret)
    pub pipes: Box<dyn Fn() -> Vec<(String, Vec<u8>)> + Send + Sync>,
    /// the person's owner branch (the seed's «mt-owner-key»)
    pub owner: Box<dyn Fn() -> Option<Vec<u8>> + Send + Sync>,
    /// a letter of a pipe opened off a channel: (reference, the letter's plain)
    pub land: Box<Land>,
    /// a wake or a point of rendezvous: something waits in the box
    pub wake: Box<dyn Fn() + Send + Sync>,
}

type FrameIds = HashSet<[u8; 16]>;

struct Holder {
    hooks: Hooks,
    ident: Ident,
    /// a door's label -> its channel, standing or being greeted
    live: Mutex<HashMap<String, Arc<Channel>>>,
    /// a door's label -> (knocked at, ms; the next step, s; refused)
    tried: Mutex<HashMap<String, (i64, f64, bool)>>,
    /// THE DOOR BOOK (iOS MontanaNodes.book): which door led to which machine, and in how long
    book: Mutex<HashMap<String, ([u8; 32], i64)>>,
    /// a door's label -> the times its machine was given our owner
    asks: Mutex<HashMap<String, u32>>,
    frames: Mutex<(FrameIds, FrameIds)>,
    knocked: AtomicBool,
}

static HOLDER: OnceLock<Arc<Holder>> = OnceLock::new();

/// Begin holding the network's machines, once, for the process's whole life.
pub fn start(hooks: Hooks, ident: Ident) {
    let h = Arc::new(Holder {
        hooks, ident, live: Default::default(), tried: Default::default(), book: Default::default(), asks: Default::default(),
        frames: Default::default(), knocked: AtomicBool::new(false),
    });
    if HOLDER.set(h.clone()).is_err() {
        return;
    }
    let k = h.clone();
    std::thread::spawn(move || loop {
        knock(&k);
        std::thread::sleep(Duration::from_secs(5)); // iOS maintainPaths: every five seconds
    });
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(8));
        warm(&h);
    });
}

fn mark(line: &str) {
    crate::trace_line(&format!("channels {line}"));
}

/// The doors this computer dials (see the head of this file).
fn dialled(d: &Door) -> bool {
    d.path.is_some() || d.port != 443
}

fn ready(h: &Holder) -> Vec<(String, Arc<Channel>)> {
    h.live.lock().unwrap().iter().filter(|(_, c)| c.ready()).map(|(l, c)| (l.clone(), c.clone())).collect()
}

/// The machines held now (iOS liveNodes): two doors to one machine are one -- the lamp stands on this, never on a count of wires.
pub fn nodes_held() -> usize {
    let Some(h) = HOLDER.get() else { return 0 };
    ready(h).iter().filter_map(|(_, c)| c.peer_tag()).collect::<HashSet<_>>().len()
}
/// Whether a knock happened in this run (iOS knockedOnce): until then «no node» means «not asked yet».
pub fn knocked() -> bool {
    HOLDER.get().is_some_and(|h| h.knocked.load(Ordering::SeqCst))
}

/// ONE MACHINE, ONE CHANNEL (iOS doorsToKnock 118-126): a door is skipped exactly when its machine is held through another door
/// right now -- a shadow cast by live holding, gone the instant the holding goes.
fn knock(h: &Arc<Holder>) {
    let doors: Vec<Door> = crate::doors::channel_doors().into_iter().filter(dialled).collect();
    let held: HashSet<String> = ready(h).into_iter().map(|(l, _)| l).collect();
    let book = h.book.lock().unwrap().clone();
    let held_nodes: HashSet<[u8; 32]> = book.iter().filter(|(l, _)| held.contains(*l)).map(|(_, (o, _))| *o).collect();
    let now = wire::now_ms();
    for d in doors {
        let label = d.label();
        if held.contains(&label) || book.get(&label).is_some_and(|(o, _)| held_nodes.contains(o)) {
            continue;
        }
        let c = {
            let mut live = h.live.lock().unwrap();
            if live.contains_key(&label) {
                continue;
            }
            let mut tried = h.tried.lock().unwrap();
            let cur = tried.get(&label).copied();
            let step = cur.map_or(STEP_MIN, |c| c.1);
            if ((now - cur.map_or(0, |c| c.0)) as f64) < step * 1000.0 {
                continue;
            }
            let spread = 0.8 + 0.6 * (crate::crypto::random(1).map_or(128, |b| b[0]) as f64 / 255.0); // the spread of a retry
            let refused = cur.is_some_and(|c| c.2);
            tried.insert(label.clone(), (now, (step * 2.0 * spread).min(if refused { STEP_DEAD_MAX } else { STEP_MAX }), refused));
            let c = channel::dialling(&d);
            live.insert(label.clone(), c.clone());
            c
        };
        h.knocked.store(true, Ordering::SeqCst);
        mark(&format!("node_knock at={label}"));
        let h2 = h.clone();
        std::thread::spawn(move || serve(&h2, c, d, label));
    }
}

fn serve(h: &Arc<Holder>, c: Arc<Channel>, d: Door, label: String) {
    let at = wire::now_ms();
    channel::run(c.clone(), Some(&d), None, &h.ident, &mut |c, heard| match heard {
        Heard::Ready => up(h, c, &label, wire::now_ms() - at),
        Heard::OwnerRef(_) => mark(&format!("owner_ref at={label}")),
        Heard::Frame(f) => received(h, c, f),
    });
    {
        let mut live = h.live.lock().unwrap();
        if live.get(&label).is_some_and(|x| Arc::ptr_eq(x, &c)) {
            live.remove(&label);
        }
        // a door that stood is knocked again at once; one that did not keeps its step and is judged refused
        let mut tried = h.tried.lock().unwrap();
        if c.ready() {
            tried.remove(&label);
        } else if let Some(t) = tried.get_mut(&label) {
            t.2 = true;
        }
    }
    h.asks.lock().unwrap().remove(&label);
    mark(&format!("node_shut at={label} why={} ready={} after_ms={}", c.close_why(), c.ready() as u8, wire::now_ms() - at));
}

/// THE CHANNEL STOOD (iOS maybeReady, onChannelUp): the door named its machine -- the knowledge outlives the channel; an extra path
/// to a machine already held closes at once; our owner leaves before anything else.
fn up(h: &Arc<Holder>, c: &Channel, label: &str, ms: i64) {
    let Some(tag) = c.peer_tag() else { return };
    h.book.lock().unwrap().insert(label.to_string(), (tag, ms));
    mark(&format!("path_up at={label} ms={ms} nodes={}", nodes_held()));
    fold(h);
    give_owner(h, c, label);
}

fn give_owner(h: &Holder, c: &Channel, label: &str) {
    let hash = c.channel_hash();
    if hash.is_empty() {
        return;
    }
    if let Some(owner) = (h.hooks.owner)() {
        *h.asks.lock().unwrap().entry(label.to_string()).or_default() += 1;
        c.send(net::OWNER_REF, &wire::owner_ref(&owner, &hash));
    }
}

/// ONE MACHINE, ONE CHANNEL (iOS foldedDoors 432-440): of the doors standing to one machine the fastest stays -- by its time to
/// stand, then by its name -- and the rest close at once.
fn fold(h: &Holder) {
    let book = h.book.lock().unwrap().clone();
    let rows: Vec<(String, Arc<Channel>, [u8; 32], i64)> = ready(h).into_iter()
        .filter_map(|(l, c)| { let (t, ms) = *book.get(&l)?; Some((l, c, t, ms)) }).collect();
    let mut best: HashMap<[u8; 32], (i64, String)> = HashMap::new();
    for (l, _, t, ms) in &rows {
        let b = best.entry(*t).or_insert((*ms, l.clone()));
        if (*ms, l) < (b.0, &b.1) {
            *b = (*ms, l.clone());
        }
    }
    for (l, c, t, ms) in rows {
        if best.get(&t).is_some_and(|b| b.1 != l) {
            mark(&format!("path_fold at={l} ms={ms}"));
            c.close("fold");
        }
    }
}

/// Every eight seconds (iOS startKeepalive 622-647, repairUnnamedOwners 648): each standing channel kept warm, a machine that has
/// not named its owner given ours again.
fn warm(h: &Holder) {
    for (l, c) in ready(h) {
        c.keepalive();
        let asked = h.asks.lock().unwrap().get(&l).copied().unwrap_or(0);
        if c.peer_owner_ref().is_none() && asked < OWNER_ASKS {
            give_owner(h, &c, &l);
        }
    }
}

/// The tags of my pipes across the accepted windows (iOS MTPipeBook.tagIndex): a tag -> (reference, secret).
fn my_pipes(h: &Holder, w: i64) -> HashMap<Vec<u8>, (String, Vec<u8>)> {
    let mut m = HashMap::new();
    for (r, s) in (h.hooks.pipes)() {
        for k in [w - 1, w, w + 1] {
            m.insert(wire::pipe_tag(&s, k), (r.clone(), s.clone()));
        }
    }
    m
}

/// A CELL THAT ARRIVED (iOS handleOverlayFrame 1318-1572): an ack ends its wait; our own frame back and a repeat go no further; a
/// frame under the tag of one of my pipes, or at my position in an accepted window, is mine -- acknowledged down the channel it
/// came by and opened; anything else is carried on.
fn received(h: &Arc<Holder>, c: &Channel, f: OverlayFrame) {
    if f.kind == OverlayFrame::ACK {
        return;
    }
    {
        let mut fr = h.frames.lock().unwrap();
        if fr.1.contains(&f.msg_id) || fr.0.contains(&f.msg_id) {
            return; // our own frame back, or a frame both doors brought
        }
        if fr.0.len() > FRAME_MEMORY {
            fr.0.clear();
        }
        fr.0.insert(f.msg_id);
    }
    let w = wire::minute();
    let under_tag = f.dst[16..].iter().all(|b| *b == 0);
    let pipe = if under_tag { my_pipes(h, w).remove(&f.dst[..16]) } else { None };
    let at_me = !under_tag && [w - 1, w, w + 1].iter().any(|k| wire::window_pos(&h.ident.tag, *k) == f.dst);
    if pipe.is_none() && !at_me {
        carry(h, c, &f, under_tag, w);
        return;
    }
    // an acknowledgement goes back down the channel it came by and addresses nobody (iOS 1426-1431)
    let ack = OverlayFrame { kind: OverlayFrame::ACK, dst: [0; 32], msg_id: f.msg_id, payload: vec![] };
    c.send(net::OVERLAY_FRAME, &ack.encode());
    mark(&format!("of_mine by={} bytes={}", if pipe.is_some() { "pipe" } else { "window-pos" }, f.payload.len()));
    let h2 = h.clone();
    std::thread::spawn(move || open(&h2, pipe, &f.payload, w)); // the channel's read never waits on a letter's landing
}

/// MY LETTER OFF A CHANNEL (iOS handleOverlayFrame 1432-1572): 0x01 ‖ the pipe's tag ‖ the body sealed with the pipe's key -- the
/// conversation is named by the letter's own tag, the pipe's seal is the proof of the sender; 0x00 ‖ a name ‖ a wake or a point of
/// rendezvous says something waits in the box. A first letter at a card's point (0x02) is not opened here yet: the box brings it.
fn open(h: &Holder, pipe: Option<(String, Vec<u8>)>, env: &[u8], w: i64) {
    match env.first() {
        Some(0x01) if env.len() > 17 => {
            let Some((r, secret)) = pipe.filter(|(_, s)| [w - 1, w, w + 1].iter().any(|k| wire::pipe_tag(s, *k) == env[1..17])) else {
                mark("open_refused -- not our pipe");
                return;
            };
            let sealed = &env[17..];
            match [w, w - 1, w + 1].iter().find_map(|k| wire::open(&wire::body_key(&secret, *k), sealed)) {
                Some(plain) => (h.hooks.land)(&r, &plain),
                None => mark("open_refused -- the pipe seal did not match"),
            }
        }
        Some(0x00) if env.len() > 65 => {
            let sealed = &env[65..];
            let is = |m: &[u8], n: usize| sealed.len() == m.len() + n && sealed.starts_with(m);
            if is(b"mt-wake", 40) || is(b"mt-wake-point", 24) {
                mark("wake_rx");
                (h.hooks.wake)();
            }
        }
        _ => {}
    }
}

/// NOT MINE (iOS 1370-1424): an envelope under a foreign tag goes on to every other machine -- its holder opens it, the rest carry
/// it, and a repeat is free because every machine filters by the frame's id; a frame at a position goes to the neighbour standing
/// at it, else to the one nearest it and strictly nearer than me, else its road ends here.
fn carry(h: &Holder, from: &Channel, f: &OverlayFrame, under_tag: bool, w: i64) {
    let others: Vec<Arc<Channel>> = ready(h).into_iter().map(|(_, c)| c)
        .filter(|c| !std::ptr::eq(c.as_ref(), from) && c.peer_tag() != from.peer_tag()).collect();
    let body = f.encode();
    if under_tag {
        for o in others {
            o.send(net::OVERLAY_FRAME, &body);
        }
        return;
    }
    if let Some(o) = others.iter().find(|o| o.peer_tag().is_some_and(|t| wire::window_pos(&t, w) == f.dst)) {
        o.send(net::OVERLAY_FRAME, &body);
        return;
    }
    let dist = |a: &[u8; 32]| -> [u8; 32] { std::array::from_fn(|i| a[i] ^ f.dst[i]) };
    let mut best = dist(&wire::window_pos(&h.ident.tag, w));
    let mut next = None;
    for o in &others {
        let Some(t) = o.peer_tag() else { continue };
        let d = dist(&wire::window_pos(&t, w));
        if d < best {
            best = d;
            next = Some(o.clone());
        }
    }
    match next {
        Some(o) => {
            o.send(net::OVERLAY_FRAME, &body);
        }
        None => mark("of_relay_drop -- nobody is nearer than us"),
    }
}

/// A LETTER LAID BEFORE THE NODES UNDER ITS PIPE'S TAG (iOS sendUnderTag 1292-1307, MontanaPath.hopMin = 1): 0x01 ‖ the pipe's tag of
/// this window ‖ the body sealed with the pipe's key of this window -- whoever holds the tag opens it, the rest carry it, and the
/// node reads nothing. Only when the path is assembled: a standing channel whose machine named its owner. The box's road goes on
/// beside it; false -- no road here.
pub fn lay(secret: &[u8], mid: &str, body: &[u8]) -> bool {
    let Some(h) = HOLDER.get() else { return false };
    let cs: Vec<Arc<Channel>> = ready(h).into_iter().map(|(_, c)| c).collect();
    if !cs.iter().any(|c| c.peer_owner_ref().is_some()) {
        return false;
    }
    let w = wire::minute();
    let tag = wire::pipe_tag(secret, w);
    let Some(sealed) = wire::seal(&wire::body_key(secret, w), body) else { return false };
    let Some(id) = crate::crypto::random(16).and_then(|b| <[u8; 16]>::try_from(b).ok()) else { return false };
    {
        let mut fr = h.frames.lock().unwrap();
        if fr.1.len() > FRAME_MEMORY {
            fr.1.clear();
        }
        fr.1.insert(id);
    }
    let mut dst = [0u8; 32];
    dst[..16].copy_from_slice(&tag);
    let frame = OverlayFrame { kind: OverlayFrame::RELAY, dst, msg_id: id, payload: [&[0x01][..], &tag, &sealed].concat() }.encode();
    let used = cs.iter().filter(|c| c.send(net::OVERLAY_FRAME, &frame)).count();
    if used > 0 {
        mark(&format!("near_tx mid={} nodes={used}", mid.chars().take(8).collect::<String>()));
    }
    used > 0
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A LETTER UNDER A PIPE'S TAG, THROUGH THE NETWORK (live, MONTANA_LIVE=1; two throwaway identities in temporary folders, a pipe
    /// secret drawn for the test): both hold the network's doors; A lays a letter under the pipe's tag before its machines, and B,
    /// holding the same pipe, opens it off its own channel -- the node read nothing of it.
    #[test]
    #[ignore]
    fn a_letter_laid_under_a_pipe_tag_reaches_its_holder_through_the_nodes() {
        if std::env::var("MONTANA_LIVE").is_err() {
            return;
        }
        let dir = std::env::temp_dir().join(format!("mt-chans-{}", wire::hex(&crate::crypto::random(6).unwrap())));
        let secret = crate::crypto::random(32).unwrap();
        let (tx, rx) = std::sync::mpsc::channel::<Vec<u8>>();
        let tx = Mutex::new(tx);
        // B: a holder of its own, hearing the pipe
        let vb = crate::vault::Vault::at(&dir.join("b")).unwrap();
        let sb = secret.clone();
        let b = Arc::new(Holder {
            hooks: Hooks {
                pipes: Box::new(move || vec![("pipe".into(), sb.clone())]),
                owner: Box::new(|| Some(vec![0x42; 32])),
                land: Box::new(move |_, plain| { let _ = tx.lock().unwrap().send(plain.to_vec()); }),
                wake: Box::new(|| {}),
            },
            ident: channel::identity(&vb).unwrap(), live: Default::default(), tried: Default::default(), book: Default::default(),
            asks: Default::default(), frames: Default::default(), knocked: AtomicBool::new(false),
        });
        // A: the process's holder
        let va = crate::vault::Vault::at(&dir.join("a")).unwrap();
        start(Hooks { pipes: Box::new(Vec::new), owner: Box::new(|| Some(vec![0x41; 32])), land: Box::new(|_, _| {}), wake: Box::new(|| {}) },
              channel::identity(&va).unwrap());
        let (b2, b3) = (b.clone(), b.clone());
        std::thread::spawn(move || loop { knock(&b2); std::thread::sleep(Duration::from_secs(2)); });
        std::thread::spawn(move || loop { std::thread::sleep(Duration::from_secs(8)); warm(&b3); });
        let end = std::time::Instant::now() + Duration::from_secs(40);
        while (nodes_held() == 0 || ready(&b).is_empty() || !ready(HOLDER.get().unwrap()).iter().any(|(_, c)| c.peer_owner_ref().is_some()))
            && std::time::Instant::now() < end {
            std::thread::sleep(Duration::from_millis(500));
        }
        println!("A holds {} machine(s), B holds {} channel(s)", nodes_held(), ready(&b).len());
        let body = b"mid:t1-LIVE\0hello through the nodes\0".to_vec();
        assert!(lay(&secret, "mid:t1-LIVE", &body), "A laid nothing: no machine named its owner");
        let got = rx.recv_timeout(Duration::from_secs(20)).expect("B opened no letter off its channel");
        assert_eq!(got, body);
        let _ = std::fs::remove_dir_all(dir);
    }
}
