//! ONE CHANNEL TO ONE DOOR (iOS 2304 MontanaDirect.swift: dial 760, initiatorHandshake 975, the registration sendNet 1020 - maybeReady 1112,
//! acceptInbound 1600; MontanaNetFrames; Android Channel.kt). A machine of the network, or a neighbour on the local network,
//! is reached by a stream: four bytes of length, big-endian, then the body, at most 1 MiB a frame. The one dialled speaks first --
//! its ML-KEM key -- then Noise_PQ XX (the core's mt_noise_*: msg1, msg2, msg3), and every frame after it is sealed under its
//! direction's key (the core's seal, ChaCha20-Poly1305). Both sides register: the answering key and its tag, a challenge, the
//! signature over the challenge and the transcript's hash (section 5.1), the verdict; the channel stands when both are confirmed.
//! Every byte of cryptography here is the core's; this file only carries frames.
//!
//! Roads: a door behind a delivery network («wss://host/path») is a web socket over the system's TLS (WinHTTP, its proxy and
//! its trust), one binary message a frame and the messages glued into one stream (Android Ws.kt, iOS MTWire 1975); a
//! neighbour's direct port is a bare TCP stream. The bare door on 443 marked «mt-node» by ALPN is the network's other road and
//! is not taken from Windows yet (WinHTTP names no ALPN of its own).

use crate::abi::*;
use crate::vault::Vault;
use crate::wire;
use std::ffi::c_void;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// The mesh's direct port (iOS MontanaDirectPort.value, Android Channels.PORT): every install listens on the same number.
pub const PORT: u16 = 8447;
/// At most a mebibyte a frame (iOS readFrame 1935).
const FRAME_MAX: usize = 1 << 20;
const MSG1: usize = 2272;
const MSG2: usize = 6349;
const MSG3: usize = 5261;
/// The handshake's own budget (iOS handshakeBudget 677): eight seconds to stand.
const GREET_MS: i64 = 8_000;
/// A standing channel hears the other side every eight seconds: thirty silent seconds are a dead road, not a quiet one.
const QUIET_MS: i64 = 30_000;

/// The messages inside a channel (iOS MontanaNetMsg, MontanaNetFrames 88-118): type[1] ‖ length[4] big-endian ‖ body.
pub mod net {
    pub const REGISTER_INIT: u8 = 0x10;
    pub const REGISTER_CHALLENGE: u8 = 0x11;
    pub const REGISTER_PROOF: u8 = 0x12;
    pub const REGISTER_RESULT: u8 = 0x13;
    pub const OWNER_REF: u8 = 0x14;
    pub const OVERLAY_FRAME: u8 = 0x20;

    pub fn encode(kind: u8, body: &[u8]) -> Vec<u8> {
        let mut out = Vec::with_capacity(5 + body.len());
        out.push(kind);
        out.extend_from_slice(&(body.len() as u32).to_be_bytes());
        out.extend_from_slice(body);
        out
    }
    pub fn decode(d: &[u8]) -> Option<(u8, &[u8])> {
        if d.len() < 5 {
            return None;
        }
        let n = u32::from_be_bytes([d[1], d[2], d[3], d[4]]) as usize;
        (d.len() == 5 + n).then(|| (d[0], &d[5..]))
    }
}

/// A cell of the overlay (iOS MontanaOverlayFrame, MontanaNetFrames 120-157): 0x02 ‖ type ‖ dst[32] ‖ msgId[16] ‖ length[4] BE ‖
/// payload.
#[derive(Debug, Clone, PartialEq)]
pub struct OverlayFrame {
    pub kind: u8,
    pub dst: [u8; 32],
    pub msg_id: [u8; 16],
    pub payload: Vec<u8>,
}
impl OverlayFrame {
    pub const RELAY: u8 = 0x01;
    pub const ACK: u8 = 0x03;
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(54 + self.payload.len());
        out.extend_from_slice(&[0x02, self.kind]);
        out.extend_from_slice(&self.dst);
        out.extend_from_slice(&self.msg_id);
        out.extend_from_slice(&(self.payload.len() as u32).to_be_bytes());
        out.extend_from_slice(&self.payload);
        out
    }
    pub fn decode(d: &[u8]) -> Option<OverlayFrame> {
        if d.len() < 54 || d[0] != 0x02 {
            return None;
        }
        let n = u32::from_be_bytes([d[50], d[51], d[52], d[53]]) as usize;
        (d.len() == 54 + n).then(|| OverlayFrame {
            kind: d[1],
            dst: d[2..34].try_into().unwrap(),
            msg_id: d[34..50].try_into().unwrap(),
            payload: d[54..].to_vec(),
        })
    }
}

/// THIS MACHINE'S ANSWERING IDENTITY (iOS MontanaOverlayKey.device, MontanaNetFrames 194-243): drawn by the core at random once
/// and kept sealed beside the person's other secrets -- never derived from the seed, so two devices of one person answer under two
/// values and nothing joins their appearances; forgotten where the person is forgotten.
pub struct Ident {
    pub pk: Vec<u8>,
    sk: Vec<u8>,
    pub tag: [u8; 32],
}
impl Ident {
    /// ML-DSA-65 over the bytes: the core's signature, 3309 bytes.
    pub fn sign(&self, msg: &[u8]) -> Option<Vec<u8>> {
        let mut sig = vec![0u8; MT_MLDSA_SIG_SIZE];
        // SAFETY: a secret key of its size, the message with its length, a signature buffer of its size
        (unsafe { mt_sign(self.sk.as_ptr(), msg.as_ptr(), msg.len(), sig.as_mut_ptr()) } == MT_OK).then_some(sig)
    }
}

const IDENT_KEY: &str = "mt.node.identity";
#[cfg(test)]
const KEM_KEY: &str = "mt.node.kem";

/// The seed of a device key: the vault's, or drawn by the core and kept there first (a seed not kept is never used).
fn device_seed(vault: &Vault, name: &str, len: usize) -> Option<Vec<u8>> {
    if let Some(s) = vault.get(name).filter(|s| s.len() == len) {
        return Some(s);
    }
    let s = crate::crypto::random(len)?;
    vault.set(name, &s).then_some(s)
}

pub fn identity(vault: &Vault) -> Option<Ident> {
    let seed = device_seed(vault, IDENT_KEY, MT_MLDSA_SEED_LEN)?;
    let (mut pk, mut sk) = (vec![0u8; MT_MLDSA_PUBKEY_SIZE], vec![0u8; MT_MLDSA_SECKEY_SIZE]);
    // SAFETY: a 32-byte seed and buffers of the sizes the door writes
    (unsafe { mt_mldsa_keypair_from_seed(seed.as_ptr(), pk.as_mut_ptr(), sk.as_mut_ptr()) } == MT_OK).then(|| {
        let tag = wire::overlay_tag(&pk);
        Ident { pk, sk, tag }
    })
}

/// THIS MACHINE'S SEALING KEY (iOS MontanaNodeKem.device, MontanaNetFrames 282-321): what a neighbour encapsulates to when it
/// dials this computer -- device-local and drawn at random, as the identity is.
#[cfg(test)]
pub fn node_kem(vault: &Vault) -> Option<(Vec<u8>, Vec<u8>)> {
    crate::crypto::mlkem_keypair(&device_seed(vault, KEM_KEY, MT_MLKEM_SEED_LEN)?)
}

/// Whether a signature over the bytes is the key's (ML-DSA-65, the core's verify).
fn verified(pk: &[u8], msg: &[u8], sig: &[u8]) -> bool {
    pk.len() == MT_MLDSA_PUBKEY_SIZE && sig.len() == MT_MLDSA_SIG_SIZE
        // SAFETY: a public key and a signature of their sizes, the message with its length
        && unsafe { mt_verify(pk.as_ptr(), msg.as_ptr(), msg.len(), sig.as_ptr()) } == MT_OK
}

/// §5.1 proof of ownership (iOS MontanaOverlayProof 245-265): «mt-reg» ‖ 0 ‖ the tag ‖ the challenge ‖ the channel's hash.
pub fn signable(tag: &[u8], challenge: &[u8], channel_hash: &[u8]) -> Vec<u8> {
    [b"mt-reg\0".as_slice(), tag, challenge, channel_hash].concat()
}

// THE HANDSHAKE'S STATES: each step consumes the one before (the core nulls it); a state abandoned between steps -- the other side
// fell silent -- goes to its own free when its holder goes.
struct Init1(*mut c_void);
struct Init2(*mut c_void);
struct Resp(*mut c_void);
impl Drop for Init1 {
    fn drop(&mut self) {
        // SAFETY: a state the core handed out and nothing consumed (a consumed one is null)
        if !self.0.is_null() { unsafe { mt_noise_state_free_initiator1(self.0) } }
    }
}
impl Drop for Init2 {
    fn drop(&mut self) {
        // SAFETY: as above
        if !self.0.is_null() { unsafe { mt_noise_state_free_initiator2(self.0) } }
    }
}
impl Drop for Resp {
    fn drop(&mut self) {
        // SAFETY: as above
        if !self.0.is_null() { unsafe { mt_noise_state_free_responder(self.0) } }
    }
}

/// The session as one side holds it: the key it sends under, the key it reads under, the transcript's hash.
pub struct Session {
    pub send: [u8; 32],
    pub recv: [u8; 32],
    pub hash: [u8; 32],
}

fn seed32() -> Option<Vec<u8>> {
    crate::crypto::random(32)
}

fn initiator1(kem_pk: &[u8]) -> Option<(Vec<u8>, Init1)> {
    if kem_pk.len() != MT_MLKEM_PUBKEY_SIZE {
        return None;
    }
    let seed = seed32()?;
    let (mut msg1, mut st) = (vec![0u8; MSG1], std::ptr::null_mut());
    // SAFETY: the key and the seed of their sizes, a msg1 buffer of its size, a place for the state
    let rc = unsafe { mt_noise_initiator_msg1(kem_pk.as_ptr(), seed.as_ptr(), msg1.as_mut_ptr(), &mut st) };
    let st = Init1(st);
    (rc == MT_OK && !st.0.is_null()).then_some((msg1, st))
}

fn initiator2(mut st: Init1, msg2: &[u8]) -> Option<Init2> {
    if msg2.len() != MSG2 {
        return None;
    }
    let mut st2 = std::ptr::null_mut();
    // SAFETY: the state the first step gave, consumed and nulled by the core whatever its answer
    let rc = unsafe { mt_noise_initiator_msg2(&mut st.0, msg2.as_ptr(), &mut st2) };
    let st2 = Init2(st2);
    (rc == MT_OK && !st2.0.is_null()).then_some(st2)
}

fn initiator3(mut st: Init2) -> Option<(Vec<u8>, Session)> {
    let (mut msg3, mut i2r, mut r2i, mut h) = (vec![0u8; MSG3], [0u8; 32], [0u8; 32], [0u8; 32]);
    // SAFETY: the second state, consumed and nulled; buffers of their sizes
    let rc = unsafe { mt_noise_initiator_msg3(&mut st.0, msg3.as_mut_ptr(), i2r.as_mut_ptr(), r2i.as_mut_ptr(), h.as_mut_ptr()) };
    // the one dialling sends initiator -> responder and reads the other way
    (rc == MT_OK).then_some((msg3, Session { send: i2r, recv: r2i, hash: h }))
}

fn responder1(kem_sk: &[u8], msg1: &[u8]) -> Option<(Vec<u8>, Resp)> {
    if kem_sk.len() != MT_MLKEM_SECKEY_SIZE || msg1.len() != MSG1 {
        return None;
    }
    let seed = seed32()?;
    let (mut msg2, mut st) = (vec![0u8; MSG2], std::ptr::null_mut());
    // SAFETY: the secret key, the seed and msg1 of their sizes, a msg2 buffer of its size, a place for the state
    let rc = unsafe { mt_noise_responder_msg1(kem_sk.as_ptr(), seed.as_ptr(), msg1.as_ptr(), msg2.as_mut_ptr(), &mut st) };
    let st = Resp(st);
    (rc == MT_OK && !st.0.is_null()).then_some((msg2, st))
}

fn responder3(mut st: Resp, msg3: &[u8]) -> Option<Session> {
    if msg3.len() != MSG3 {
        return None;
    }
    let (mut i2r, mut r2i, mut h) = ([0u8; 32], [0u8; 32], [0u8; 32]);
    // SAFETY: the responder's state, consumed and nulled; buffers of their sizes
    let rc = unsafe { mt_noise_responder_msg3(&mut st.0, msg3.as_ptr(), i2r.as_mut_ptr(), r2i.as_mut_ptr(), h.as_mut_ptr()) };
    // the one dialled sends responder -> initiator and reads initiator -> responder
    (rc == MT_OK).then_some(Session { send: r2i, recv: i2r, hash: h })
}

/// A door of the network's list, or a neighbour's address (iOS MontanaNodes.Node 38-52): bare, or behind a delivery network
/// with the web socket's path.
#[derive(Debug, Clone, PartialEq)]
pub struct Door {
    pub host: String,
    pub port: u16,
    pub path: Option<String>,
}
impl Door {
    /// A door's name, one place for the list, the book and the channel (iOS MontanaNodes.Node.label 42-46, doorKey 60-65).
    pub fn label(&self) -> String {
        let at = if self.host.contains(':') { format!("[{}]:{}", self.host, self.port) } else { format!("{}:{}", self.host, self.port) };
        if self.path.is_some() { format!("wss/{at}") } else { at }
    }

    /// iOS MontanaNodes.parse 185-228: «wss://name/path» is a door behind a delivery network on 443; «[v6]:port», «host:port»; the
    /// port defaults to the direct one.
    pub fn parse(w: &str) -> Option<Door> {
        let w = w.trim();
        if w.is_empty() || w.starts_with('#') {
            return None;
        }
        if let Some(body) = w.strip_prefix("wss://").or_else(|| w.strip_prefix("WSS://")) {
            let (host, path) = match body.split_once('/') {
                Some((h, p)) => (h, format!("/{p}")),
                None => (body, "/".to_string()),
            };
            return (!host.is_empty()).then(|| Door { host: host.to_string(), port: 443, path: Some(path) });
        }
        if let Some(rest) = w.strip_prefix('[') {
            let (host, tail) = rest.split_once(']')?;
            let port = tail.strip_prefix(':').and_then(|p| p.parse::<u16>().ok()).filter(|p| *p > 0).unwrap_or(PORT);
            return (!host.is_empty()).then(|| Door { host: host.to_string(), port, path: None });
        }
        let (host, port) = match w.split_once(':') {
            Some((h, p)) if !p.contains(':') => (h, p.parse::<u16>().ok().filter(|p| *p > 0)?),
            _ => (w, PORT),
        };
        (!host.is_empty()).then(|| Door { host: host.to_string(), port, path: None })
    }
}

/// THE ROAD UNDER A CHANNEL: what it reads glued into one stream, what it writes one frame at a time.
enum Reader {
    Tcp(TcpStream),
    Ws(ws::Reader),
}
enum Writer {
    Tcp(TcpStream),
    Ws(Arc<ws::Pipe>),
}
impl Reader {
    fn read_exact(&mut self, buf: &mut [u8]) -> bool {
        match self {
            Reader::Tcp(s) => s.read_exact(buf).is_ok(),
            Reader::Ws(r) => r.read_exact(buf),
        }
    }
}
impl Writer {
    fn write(&mut self, frame: &[u8]) -> bool {
        match self {
            Writer::Tcp(s) => s.write_all(frame).and_then(|_| s.flush()).is_ok(),
            Writer::Ws(p) => p.send(frame),
        }
    }
}

/// ONE CHANNEL: greeted as the one dialling or as the one dialled, then read until it dies. Its state is read by the holder
/// while the channel's own thread reads the road.
pub struct Channel {
    // the door's name, its host and the moment it was dialled, for a reader of the channel; only a test reads one yet
    #[allow(dead_code)]
    pub label: String,
    #[allow(dead_code)]
    pub host: String,
    #[allow(dead_code)]
    pub dial_at: i64,
    ready: AtomicBool,
    closed: AtomicBool,
    heard_at: AtomicI64,
    /// The peer's overlay tag, confirmed by its registration (iOS peerOverlay, §5.3).
    peer_tag: Mutex<Option<[u8; 32]>>,
    /// The owner reference the peer named on this channel (iOS peerOwnerRef).
    peer_owner_ref: Mutex<Option<Vec<u8>>>,
    close_why: Mutex<String>,
    hash: Mutex<Vec<u8>>,
    send_key: Mutex<Option<[u8; 32]>>,
    writer: Mutex<Option<Writer>>,
    shut: Mutex<Option<Shut>>,
}

/// How a road is cut from outside (a watchdog, a close): the TCP stream's shutdown, the web socket's handle.
enum Shut {
    Tcp(TcpStream),
    Ws(Arc<ws::Pipe>),
}

/// What happens on a channel, told to its holder.
pub enum Heard {
    /// Both registrations confirmed: the channel stands.
    Ready,
    /// The peer named its owner (16 bytes, iOS MontanaNetMsg.ownerRef); the holder marks it, nothing reads the bytes yet.
    #[allow(dead_code)]
    OwnerRef(Vec<u8>),
    /// A cell of the overlay.
    Frame(OverlayFrame),
}

impl Channel {
    fn new(label: String, host: String) -> Channel {
        let now = wire::now_ms();
        Channel {
            label,
            host,
            dial_at: now,
            ready: AtomicBool::new(false),
            closed: AtomicBool::new(false),
            heard_at: AtomicI64::new(now),
            peer_tag: Mutex::new(None),
            peer_owner_ref: Mutex::new(None),
            close_why: Mutex::new(String::new()),
            hash: Mutex::new(vec![]),
            send_key: Mutex::new(None),
            writer: Mutex::new(None),
            shut: Mutex::new(None),
        }
    }
    pub fn ready(&self) -> bool {
        self.ready.load(Ordering::SeqCst)
    }
    pub fn peer_tag(&self) -> Option<[u8; 32]> {
        *self.peer_tag.lock().unwrap()
    }
    pub fn peer_owner_ref(&self) -> Option<Vec<u8>> {
        self.peer_owner_ref.lock().unwrap().clone()
    }
    pub fn channel_hash(&self) -> Vec<u8> {
        self.hash.lock().unwrap().clone()
    }
    pub fn close_why(&self) -> String {
        self.close_why.lock().unwrap().clone()
    }
    pub fn heard_at(&self) -> i64 {
        self.heard_at.load(Ordering::SeqCst)
    }

    /// The channel ends, and its first reason stands: a later one is only the echo of the first.
    pub fn close(&self, why: &str) {
        {
            let mut w = self.close_why.lock().unwrap();
            if w.is_empty() {
                *w = why.to_string();
            }
        }
        if self.closed.swap(true, Ordering::SeqCst) {
            return;
        }
        match self.shut.lock().unwrap().take() {
            Some(Shut::Tcp(s)) => {
                let _ = s.shutdown(std::net::Shutdown::Both);
            }
            Some(Shut::Ws(p)) => p.close(),
            None => {}
        }
    }

    fn write_raw(&self, body: &[u8]) -> bool {
        if body.len() > FRAME_MAX {
            return false;
        }
        let frame = [&(body.len() as u32).to_be_bytes()[..], body].concat();
        let mut w = self.writer.lock().unwrap();
        w.as_mut().is_some_and(|w| w.write(&frame))
    }

    /// One sealed message of the channel (iOS sendNet 1020): false -- the channel could not take it.
    pub fn send(&self, kind: u8, body: &[u8]) -> bool {
        self.sealed(&net::encode(kind, body))
    }
    fn sealed(&self, plain: &[u8]) -> bool {
        let Some(k) = *self.send_key.lock().unwrap() else { return false };
        let Some(s) = wire::seal(&k, plain) else { return false };
        self.write_raw(&s)
    }
    /// The frame that keeps a standing channel warm (iOS startKeepalive 622): [0x02], sealed.
    pub fn keepalive(&self) -> bool {
        self.sealed(&[0x02])
    }
}

fn read_frame(r: &mut Reader) -> Option<Vec<u8>> {
    let mut n = [0u8; 4];
    if !r.read_exact(&mut n) {
        return None;
    }
    let n = u32::from_be_bytes(n) as usize;
    if n == 0 || n > FRAME_MAX {
        return None;
    }
    let mut body = vec![0u8; n];
    r.read_exact(&mut body).then_some(body)
}

/// A dial: the road to the door stands (five seconds to connect, iOS dial), the channel's writer and its cutter laid in.
fn road_to(c: &Channel, d: &Door) -> Option<Reader> {
    if let Some(path) = &d.path {
        let pipe = Arc::new(ws::Pipe::open(&d.host, d.port, path, 8_000)?);
        *c.writer.lock().unwrap() = Some(Writer::Ws(pipe.clone()));
        *c.shut.lock().unwrap() = Some(Shut::Ws(pipe.clone()));
        return Some(Reader::Ws(ws::Reader::new(pipe)));
    }
    let addr: SocketAddr = (d.host.as_str(), d.port).to_socket_addrs().ok()?.next()?;
    let s = TcpStream::connect_timeout(&addr, Duration::from_secs(5)).ok()?;
    let _ = s.set_nodelay(true);
    *c.writer.lock().unwrap() = Some(Writer::Tcp(s.try_clone().ok()?));
    *c.shut.lock().unwrap() = Some(Shut::Tcp(s.try_clone().ok()?));
    Some(Reader::Tcp(s))
}

/// The one dialling (iOS dial 760, initiatorHandshake 975): the far side's KEM key, msg1, msg2, msg3.
fn greet_as_dialler(c: &Channel, r: &mut Reader) -> Result<Session, &'static str> {
    let kem = read_frame(r).filter(|k| k.len() == MT_MLKEM_PUBKEY_SIZE).ok_or("noise-key")?;
    let (msg1, st1) = initiator1(&kem).ok_or("noise-msg1")?;
    if !c.write_raw(&msg1) {
        return Err("noise-msg1-write");
    }
    let msg2 = read_frame(r).filter(|m| m.len() == MSG2).ok_or("noise-msg2")?;
    let st2 = initiator2(st1, &msg2).ok_or("noise-msg2-open")?;
    let (msg3, s) = initiator3(st2).ok_or("noise-msg3")?;
    if !c.write_raw(&msg3) {
        return Err("noise-msg3-write");
    }
    Ok(s)
}

/// The one dialled (iOS acceptInbound 1600): my KEM key first, then msg1 -> msg2 -> msg3; the keys are the dialler's mirror.
fn greet_as_dialled(c: &Channel, r: &mut Reader, kem: &(Vec<u8>, Vec<u8>)) -> Result<Session, &'static str> {
    if !c.write_raw(&kem.0) {
        return Err("kem-write");
    }
    let msg1 = read_frame(r).filter(|m| m.len() == MSG1).ok_or("noise-msg1")?;
    let (msg2, st) = responder1(&kem.1, &msg1).ok_or("noise-msg2")?;
    if !c.write_raw(&msg2) {
        return Err("noise-msg2-write");
    }
    let msg3 = read_frame(r).filter(|m| m.len() == MSG3).ok_or("noise-msg3")?;
    responder3(st, &msg3).ok_or("noise-msg3-open")
}

/// The watchdog of a channel: silent beyond its budget -- eight seconds to stand, thirty once standing -- the road is cut, and the
/// reading thread ends with it.
fn watch(c: Arc<Channel>) {
    std::thread::spawn(move || {
        while !c.closed.load(Ordering::SeqCst) {
            std::thread::sleep(Duration::from_millis(500));
            let budget = if c.ready() { QUIET_MS } else { GREET_MS };
            if wire::now_ms() - c.heard_at() > budget {
                c.close(if c.ready() { "silent" } else { "greet-timeout" });
            }
        }
    });
}

type Accepted = (TcpStream, (Vec<u8>, Vec<u8>));

/// Greets and reads until the channel dies, on the caller's thread; `hear` is told what the channel says. `accepted` -- a
/// neighbour that dialled this computer (its stream and this machine's KEM pair), else the door is dialled.
pub fn run(c: Arc<Channel>, door: Option<&Door>, accepted: Option<Accepted>, ident: &Ident,
           hear: &mut dyn FnMut(&Channel, Heard)) {
    watch(c.clone());
    let reader = match (door, &accepted) {
        (_, Some((s, _))) => {
            let (w, sh) = (s.try_clone(), s.try_clone());
            match (w, sh) {
                (Ok(w), Ok(sh)) => {
                    *c.writer.lock().unwrap() = Some(Writer::Tcp(w));
                    *c.shut.lock().unwrap() = Some(Shut::Tcp(sh));
                    s.try_clone().ok().map(Reader::Tcp)
                }
                _ => None,
            }
        }
        (Some(d), None) => road_to(&c, d),
        (None, None) => None,
    };
    let Some(mut r) = reader else {
        c.close("dial");
        return;
    };
    if c.closed.load(Ordering::SeqCst) {
        return;
    }
    c.heard_at.store(wire::now_ms(), Ordering::SeqCst);
    let session = match &accepted {
        Some((_, kem)) => greet_as_dialled(&c, &mut r, kem),
        None => greet_as_dialler(&c, &mut r),
    };
    let s = match session {
        Ok(s) => s,
        Err(why) => {
            c.close(why);
            return;
        }
    };
    *c.hash.lock().unwrap() = s.hash.to_vec();
    *c.send_key.lock().unwrap() = Some(s.send);
    c.heard_at.store(wire::now_ms(), Ordering::SeqCst);
    let mut reg = Registration::default();
    if !c.send(net::REGISTER_INIT, &[ident.pk.as_slice(), &ident.tag].concat()) {
        c.close("reg-write");
        return;
    }
    loop {
        let Some(f) = read_frame(&mut r) else {
            c.close("peer-closed");
            return;
        };
        let Some(plain) = wire::open(&s.recv, &f) else {
            c.close("bad-frame");
            return;
        };
        c.heard_at.store(wire::now_ms(), Ordering::SeqCst);
        if plain == [0x02] {
            continue; // the other side's keepalive
        }
        let Some((kind, body)) = net::decode(&plain) else { continue };
        match kind {
            net::REGISTER_INIT => reg.init(&c, body),
            net::REGISTER_CHALLENGE => {
                if body.len() == 16 {
                    if let Some(sig) = ident.sign(&signable(&ident.tag, body, &s.hash)) {
                        c.send(net::REGISTER_PROOF, &sig);
                    }
                }
            }
            net::REGISTER_PROOF => {
                if reg.proof(&c, body, &s.hash) && reg.both() && !c.ready.swap(true, Ordering::SeqCst) {
                    hear(&c, Heard::Ready);
                }
            }
            net::REGISTER_RESULT => {
                if body.first() == Some(&0) {
                    reg.mine = true;
                    if reg.both() && !c.ready.swap(true, Ordering::SeqCst) {
                        hear(&c, Heard::Ready);
                    }
                }
            }
            net::OWNER_REF => {
                if body.len() == 16 && c.peer_owner_ref.lock().unwrap().is_none() {
                    *c.peer_owner_ref.lock().unwrap() = Some(body.to_vec());
                    hear(&c, Heard::OwnerRef(body.to_vec()));
                }
            }
            net::OVERLAY_FRAME => {
                if let Some(of) = OverlayFrame::decode(body) {
                    hear(&c, Heard::Frame(of));
                }
            }
            _ => {}
        }
    }
}

/// Both registrations of one channel (iOS sendNet 1020 - maybeReady 1112): the peer's key and tag, the challenge this side drew, the two verdicts.
#[derive(Default)]
struct Registration {
    peer_pk: Option<Vec<u8>>,
    nonce: Option<Vec<u8>>,
    mine: bool,
    theirs: bool,
}
impl Registration {
    fn both(&self) -> bool {
        self.mine && self.theirs
    }
    /// The peer's key and its tag (1952 ‖ 32): the tag is the key's own (§3.3), and a challenge is drawn for it.
    fn init(&mut self, c: &Channel, body: &[u8]) {
        if body.len() != MT_MLDSA_PUBKEY_SIZE + 32 {
            return;
        }
        let (pk, tag) = body.split_at(MT_MLDSA_PUBKEY_SIZE);
        if wire::overlay_tag(pk) != tag {
            return;
        }
        let Some(n) = crate::crypto::random(16) else {
            c.close("no-nonce");
            return;
        };
        self.peer_pk = Some(pk.to_vec());
        *c.peer_tag.lock().unwrap() = Some(tag.try_into().unwrap());
        self.nonce = Some(n.clone());
        c.send(net::REGISTER_CHALLENGE, &n);
    }
    /// The peer's signature over its tag, my challenge and the channel's hash: the verdict told back.
    fn proof(&mut self, c: &Channel, sig: &[u8], hash: &[u8]) -> bool {
        let tag = c.peer_tag();
        let ok = match (&self.peer_pk, &self.nonce, tag) {
            (Some(pk), Some(n), Some(t)) => verified(pk, &signable(&t, n, hash), sig),
            _ => false,
        };
        c.send(net::REGISTER_RESULT, &[if ok { 0x00 } else { 0x01 }]);
        self.theirs = ok;
        ok
    }
}

/// A channel to dial: its name and the host it goes to.
pub fn dialling(d: &Door) -> Arc<Channel> {
    Arc::new(Channel::new(d.label(), d.host.clone()))
}

/// A channel of a neighbour that dialled this computer.
#[cfg(test)]
pub fn answering(peer: &SocketAddr) -> Arc<Channel> {
    let host = peer.ip().to_string();
    let label = format!("in:{}", if host.contains(':') { format!("[{host}]:{}", peer.port()) } else { format!("{host}:{}", peer.port()) });
    Arc::new(Channel::new(label, host))
}

/// A WEB SOCKET IS A PIPE, NOT A LAYOUT (Android Ws.kt, iOS MTWire 1975): the system's own rise (RFC 6455) through WinHTTP --
/// its TLS, its proxy, its trust; a frame leaves as one binary message, and the messages read are glued into one stream. WinHTTP
/// answers a ping by itself; a close is the end of the stream.
mod ws {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Arc, Mutex};

    pub struct Pipe {
        session: usize,
        connect: usize,
        socket: usize,
        closed: AtomicBool,
        sending: Mutex<()>,
    }
    // SAFETY: WinHTTP's handles are free-threaded; one thread receives while another sends under the pipe's lock
    unsafe impl Send for Pipe {}
    unsafe impl Sync for Pipe {}

    #[cfg(windows)]
    impl Pipe {
        pub fn open(host: &str, port: u16, path: &str, timeout_ms: u32) -> Option<Pipe> {
            use std::ptr::{null, null_mut};
            use windows_sys::Win32::Networking::WinHttp::*;
            fn wide(s: &str) -> Vec<u16> {
                s.encode_utf16().chain(std::iter::once(0)).collect()
            }
            // SAFETY: every handle is checked; on every failure the ones opened are closed before the return
            unsafe {
                let session = WinHttpOpen(wide("Montana-Windows/0.1").as_ptr(), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, null(), null(), 0);
                if session.is_null() {
                    return None;
                }
                let t = timeout_ms as i32;
                WinHttpSetTimeouts(session, t, t, t, t);
                let connect = WinHttpConnect(session, wide(host).as_ptr(), port, 0);
                if connect.is_null() {
                    WinHttpCloseHandle(session);
                    return None;
                }
                let request = WinHttpOpenRequest(connect, wide("GET").as_ptr(), wide(path).as_ptr(), null(), null(), null(), WINHTTP_FLAG_SECURE);
                let up = !request.is_null()
                    && WinHttpSetOption(request, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, null_mut(), 0) != 0
                    && WinHttpSendRequest(request, null(), 0, null(), 0, 0, 0) != 0
                    && WinHttpReceiveResponse(request, null_mut()) != 0
                    && {
                        let mut code: u32 = 0;
                        let mut size = std::mem::size_of::<u32>() as u32;
                        WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, null(),
                                            &mut code as *mut u32 as *mut _, &mut size, null_mut()) != 0 && code == 101
                    };
                let socket = if up { WinHttpWebSocketCompleteUpgrade(request, 0) } else { null_mut() };
                if !request.is_null() {
                    WinHttpCloseHandle(request);
                }
                if socket.is_null() {
                    WinHttpCloseHandle(connect);
                    WinHttpCloseHandle(session);
                    return None;
                }
                Some(Pipe { session: session as usize, connect: connect as usize, socket: socket as usize, closed: AtomicBool::new(false),
                            sending: Mutex::new(()) })
            }
        }

        /// One frame, one binary message.
        pub fn send(&self, frame: &[u8]) -> bool {
            use windows_sys::Win32::Networking::WinHttp::*;
            let _one = self.sending.lock().unwrap();
            if self.closed.load(Ordering::SeqCst) {
                return false;
            }
            // SAFETY: a live socket handle and the frame with its length
            unsafe { WinHttpWebSocketSend(self.socket as *const _, WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE, frame.as_ptr() as *const _,
                                          frame.len() as u32) == 0 }
        }

        /// The next bytes of the stream, or None: the other side closed, or the pipe was cut.
        pub fn receive(&self) -> Option<Vec<u8>> {
            use windows_sys::Win32::Networking::WinHttp::*;
            let mut buf = vec![0u8; 64 * 1024];
            loop {
                if self.closed.load(Ordering::SeqCst) {
                    return None;
                }
                let (mut read, mut kind) = (0u32, 0i32);
                // SAFETY: a live socket handle and a buffer of its length
                let rc = unsafe { WinHttpWebSocketReceive(self.socket as *const _, buf.as_mut_ptr() as *mut _, buf.len() as u32, &mut read, &mut kind) };
                if rc != 0 || kind == WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE {
                    return None;
                }
                if read > 0 {
                    buf.truncate(read as usize);
                    return Some(buf);
                }
            }
        }

        /// The pipe is cut: a receive waiting ends at once.
        pub fn close(&self) {
            if self.closed.swap(true, Ordering::SeqCst) {
                return;
            }
            let _one = self.sending.lock().unwrap();
            // SAFETY: each handle closed once (the flag above), the socket first
            unsafe {
                use windows_sys::Win32::Networking::WinHttp::WinHttpCloseHandle;
                WinHttpCloseHandle(self.socket as *mut _);
                WinHttpCloseHandle(self.connect as *mut _);
                WinHttpCloseHandle(self.session as *mut _);
            }
        }
    }
    #[cfg(not(windows))]
    impl Pipe {
        pub fn open(_: &str, _: u16, _: &str, _: u32) -> Option<Pipe> { None }
        pub fn send(&self, _: &[u8]) -> bool { false }
        pub fn receive(&self) -> Option<Vec<u8>> { None }
        pub fn close(&self) {}
    }
    impl Drop for Pipe {
        fn drop(&mut self) {
            self.close();
        }
    }

    /// The messages read, glued into one stream the frame reader takes exactly as much from.
    pub struct Reader {
        pipe: Arc<Pipe>,
        buf: Vec<u8>,
        at: usize,
    }
    impl Reader {
        pub fn new(pipe: Arc<Pipe>) -> Reader {
            Reader { pipe, buf: vec![], at: 0 }
        }
        pub fn read_exact(&mut self, out: &mut [u8]) -> bool {
            let mut got = 0;
            while got < out.len() {
                if self.at >= self.buf.len() {
                    match self.pipe.receive() {
                        Some(b) => {
                            self.buf = b;
                            self.at = 0;
                        }
                        None => return false,
                    }
                }
                let n = (out.len() - got).min(self.buf.len() - self.at);
                out[got..got + n].copy_from_slice(&self.buf[self.at..self.at + n]);
                got += n;
                self.at += n;
            }
            true
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_door_of_the_list_is_read_as_its_road() {
        assert_eq!(Door::parse("wss://door.montana.quest/ws"), Some(Door { host: "door.montana.quest".into(), port: 443, path: Some("/ws".into()) }));
        assert_eq!(Door::parse("api.montana.quest:443"), Some(Door { host: "api.montana.quest".into(), port: 443, path: None }));
        assert_eq!(Door::parse("[2001:db8::1]:9000"), Some(Door { host: "2001:db8::1".into(), port: 9000, path: None }));
        assert_eq!(Door::parse("192.168.1.5"), Some(Door { host: "192.168.1.5".into(), port: PORT, path: None }));
        assert_eq!(Door::parse("# a comment"), None);
        assert_eq!(Door::parse("wss://door.montana.quest/ws").unwrap().label(), "wss/door.montana.quest:443");
        assert_eq!(Door::parse("[2001:db8::1]:9000").unwrap().label(), "[2001:db8::1]:9000");
    }

    #[test]
    fn a_message_and_a_cell_of_the_overlay_keep_their_layout() {
        let m = net::encode(net::OWNER_REF, &[7u8; 16]);
        assert_eq!((m[0], &m[1..5], m.len()), (0x14, &[0u8, 0, 0, 16][..], 21));
        assert_eq!(net::decode(&m), Some((0x14, &[7u8; 16][..])));
        assert_eq!(net::decode(&m[..20]), None, "a cut message is no message");
        let f = OverlayFrame { kind: OverlayFrame::RELAY, dst: [1; 32], msg_id: [2; 16], payload: b"letter".to_vec() };
        let e = f.encode();
        assert_eq!((e[0], e[1], e.len()), (0x02, 0x01, 54 + 6));
        assert_eq!(OverlayFrame::decode(&e), Some(f));
        assert_eq!(OverlayFrame::decode(&e[..59]), None);
    }

    /// TWO SIDES OF ONE CHANNEL ON THIS MACHINE: a listener with its KEM pair answers, a dialler greets it; Noise_PQ gives both the
    /// same transcript hash and mirrored keys, both register with their own identities, and a cell of the overlay crosses sealed.
    #[test]
    fn two_machines_greet_register_and_carry_a_cell() {
        let dir = std::env::temp_dir().join(format!("mt-chan-{}", wire::hex(&crate::crypto::random(6).unwrap())));
        let (va, vb) = (Vault::at(&dir.join("a")).unwrap(), Vault::at(&dir.join("b")).unwrap());
        let (ia, ib) = (identity(&va).unwrap(), identity(&vb).unwrap());
        assert_eq!(identity(&va).unwrap().tag, ia.tag, "the identity is kept, not drawn again");
        assert_ne!(ia.tag, ib.tag);
        let kem = node_kem(&vb).unwrap();
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let (tx, rx) = std::sync::mpsc::channel::<(String, Vec<u8>)>();
        let tb = tx.clone();
        let b_tag = ib.tag;
        let answer = std::thread::spawn(move || {
            let (s, peer) = listener.accept().unwrap();
            let c = answering(&peer);
            run(c.clone(), None, Some((s, kem)), &ib, &mut |c, h| match h {
                Heard::Ready => tb.send(("b-ready".into(), c.peer_tag().unwrap().to_vec())).unwrap(),
                Heard::Frame(f) => {
                    tb.send(("b-frame".into(), f.payload.clone())).unwrap();
                    c.close("done");
                }
                Heard::OwnerRef(_) => {}
            });
        });
        let door = Door { host: "127.0.0.1".into(), port, path: None };
        let a = dialling(&door);
        let a2 = a.clone();
        let ta = tx.clone();
        let dial = std::thread::spawn(move || {
            run(a2, Some(&door), None, &ia, &mut |c, h| {
                if let Heard::Ready = h {
                    ta.send(("a-ready".into(), c.peer_tag().unwrap().to_vec())).unwrap();
                    let f = OverlayFrame { kind: OverlayFrame::RELAY, dst: [9; 32], msg_id: [3; 16], payload: b"near letter".to_vec() };
                    assert!(c.send(net::OVERLAY_FRAME, &f.encode()));
                }
            });
        });
        let mut got = std::collections::HashMap::new();
        while got.len() < 3 {
            let (k, v) = rx.recv_timeout(Duration::from_secs(20)).expect("the channel stands and carries");
            got.insert(k, v);
        }
        assert_eq!(got["a-ready"], b_tag.to_vec(), "the dialler holds the answering machine's registered tag");
        assert_eq!(got["b-frame"], b"near letter".to_vec());
        answer.join().unwrap();
        a.close("test-end");
        dial.join().unwrap();
        let _ = std::fs::remove_dir_all(dir);
    }

    /// A NODE OF THE NETWORK, LIVE (no personal data: a throwaway identity in a temporary folder): every door behind a delivery
    /// network the shipped and the learned lists name is dialled, and at least one channel stands -- Noise_PQ with the node's own
    /// KEM key and both registrations confirmed -- each door's time told.
    #[test]
    #[ignore]
    fn a_door_of_the_network_greets_and_registers_this_machine() {
        if std::env::var("MONTANA_LIVE").is_err() {
            return;
        }
        let dir = std::env::temp_dir().join(format!("mt-chan-live-{}", wire::hex(&crate::crypto::random(6).unwrap())));
        let v = Vault::at(&dir).unwrap();
        let mut stood = 0;
        for d in crate::doors::channel_doors().into_iter().filter(|d| d.path.is_some()) {
            let me = identity(&v).unwrap();
            let c = dialling(&d);
            let (tx, rx) = std::sync::mpsc::channel();
            let c2 = c.clone();
            let d2 = d.clone();
            let t = std::thread::spawn(move || {
                run(c2, Some(&d2), None, &me, &mut |c, h| {
                    if let Heard::Ready = h {
                        let _ = tx.send(c.peer_tag());
                    }
                })
            });
            let tag = rx.recv_timeout(Duration::from_secs(15)).ok().flatten();
            println!("door {} ready={} ms={} why={}", d.label(), tag.is_some(), wire::now_ms() - c.dial_at, c.close_why());
            if tag.is_some() {
                stood += 1;
                assert!(c.keepalive(), "a standing channel takes its keepalive");
            }
            c.close("test-end");
            let _ = t.join();
        }
        assert!(stood > 0, "no door of the network greeted this machine");
        let _ = std::fs::remove_dir_all(dir);
    }
}
