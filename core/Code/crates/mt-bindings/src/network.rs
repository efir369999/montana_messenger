//! C-ABI of the network bridge (Montana P2P Network, Stage 6): synchronous wrappers over the
//! network core (mt-postman/rendezvous/bootstrap) for Swift/Kotlin. Native-only —
//! tokio/quinn do not compile to wasm. Model: global tokio runtime, blocking
//! FFI calls (block_on). A panic across the C boundary = UB, so all errors are
//! reported via NULL/return code, without unwrap/panic on the FFI path.
//!
//! Thread-safety: handles (MtPostman/MtClient/MtMdns) are Send+Sync, safe to
//! pass and use from any thread. Concurrent calls on the SAME handle
//! are allowed (Sync), but the ordering of operations across threads is not guaranteed.

use std::collections::VecDeque;
use std::ffi::{CStr, CString};
use std::net::SocketAddr;
use std::os::raw::c_char;
use std::sync::{Arc, Mutex, OnceLock};

use zeroize::Zeroize;

use mt_crypto::{MlkemPublicKey, SecretKey, SECRET_KEY_SIZE};
use mt_overlay::muq::{sign_deposit, HostDeposit, ProxyForward, Queue, QueueItem};
use mt_postman::{MuqClient, MuqState, PostmanServer};

fn rt() -> Option<&'static tokio::runtime::Runtime> {
    static RT: OnceLock<Option<tokio::runtime::Runtime>> = OnceLock::new();
    RT.get_or_init(|| tokio::runtime::Runtime::new().ok())
        .as_ref()
}

/// N-1: a future panic must not cross the C boundary (UB). Wrap block_on in
/// catch_unwind; panic → None → FFI error code.
fn ffi_catch<R>(f: impl FnOnce() -> R) -> Option<R> {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)).ok()
}

/// Opaque handle to a live postman for FFI. Holds the address, the loop task (for shutdown)
/// and MuqState (courier routes).
pub struct MtPostman {
    addr: SocketAddr,
    task: tokio::task::JoinHandle<()>,
    muq: Arc<MuqState>,
}

/// # Safety
/// `bind` is a valid C string (null-terminated) or null. The caller owns it.
unsafe fn cstr_to_socketaddr(bind: *const c_char) -> Option<SocketAddr> {
    if bind.is_null() {
        return None;
    }
    CStr::from_ptr(bind).to_str().ok()?.parse().ok()
}

/// Start a postman on `bind` (for example "0.0.0.0:0"). On success writes the real
/// address (host:port) into `out_addr` (a buffer of capacity `out_cap`, null-terminated) and returns
/// an opaque handle; on error, null. The handle is freed by `mt_postman_stop`.
///
/// # Safety
/// `bind` is a valid C string; `out_addr` is a buffer ≥ `out_cap` bytes or null.
#[no_mangle]
pub unsafe extern "C" fn mt_postman_start(
    bind: *const c_char,
    out_addr: *mut c_char,
    out_cap: usize,
) -> *mut MtPostman {
    let Some(addr) = cstr_to_socketaddr(bind) else {
        return std::ptr::null_mut();
    };
    let Some(rt) = rt() else {
        return std::ptr::null_mut();
    };
    let Ok(server) = rt.block_on(PostmanServer::bind(addr)) else {
        return std::ptr::null_mut();
    };
    let Ok(real_addr) = server.local_addr() else {
        return std::ptr::null_mut();
    };
    let muq = server.muq().clone();

    // Self-host (spec §534, "SELF-HOST absolute against collusion"): a phone-node = courier+host,
    // self-routes host_overlay → loopback → accepts a deposit into ITS OWN queue without a central
    // server. host_overlay = SHA-256(host_kem_pk) (the same derivation as client/manifest).
    {
        let host_kem = muq.host_kem_pubkey();
        let overlay = mt_crypto::sha256_raw(&host_kem.as_bytes()[..]);
        if let Ok(loopback) = format!("127.0.0.1:{}", real_addr.port()).parse() {
            muq.add_proxy_route(overlay, loopback);
        }
    }

    let task = rt.spawn(server.run());

    // write the real address into out_addr if requested
    if !out_addr.is_null() && out_cap > 0 {
        if let Ok(cs) = CString::new(real_addr.to_string()) {
            let bytes = cs.as_bytes_with_nul();
            if bytes.len() <= out_cap {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_addr as *mut u8, bytes.len());
            }
        }
    }

    Box::into_raw(Box::new(MtPostman {
        addr: real_addr,
        task,
        muq,
    }))
}

/// Stop the postman and free the handle. After the call `h` is invalid.
///
/// # Safety
/// `h` is a handle from `mt_postman_start` or null; do not reuse.
#[no_mangle]
pub unsafe extern "C" fn mt_postman_stop(h: *mut MtPostman) {
    if h.is_null() {
        return;
    }
    let postman = Box::from_raw(h);
    postman.task.abort();
    // Box drop frees MtPostman; muq (Arc) refcount decreases.
}

/// Port of a live postman (0 for a null handle) — for diagnostics/testing.
///
/// # Safety
/// `h` is a valid handle from `mt_postman_start` or null.
#[no_mangle]
pub unsafe extern "C" fn mt_postman_port(h: *const MtPostman) -> u16 {
    if h.is_null() {
        return 0;
    }
    (*h).addr.port()
}

/// Add a courier route: `overlay` (32 B host overlay address) → physical `target`
/// (host:port). Returns 0 on success, -1 on argument error. Stage 3 relay model.
///
/// # Safety
/// `h` is a valid handle; `overlay` is a pointer to 32 bytes; `target` is a C string.
#[no_mangle]
pub unsafe extern "C" fn mt_postman_add_route(
    h: *const MtPostman,
    overlay: *const u8,
    target: *const c_char,
) -> i32 {
    if h.is_null() || overlay.is_null() {
        return -1;
    }
    let Some(addr) = cstr_to_socketaddr(target) else {
        return -1;
    };
    let mut ov = [0u8; 32];
    std::ptr::copy_nonoverlapping(overlay, ov.as_mut_ptr(), 32);
    (*h).muq().add_proxy_route(ov, addr);
    0
}

/// Write the postman's ML-KEM pubkey (1184 B) into `out` (capacity `out_cap`). The client
/// uses it for a sealed deposit. Returns the number of bytes written (0 on error).
///
/// # Safety
/// `h` is a valid handle; `out` is a buffer ≥ `out_cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_postman_kem_pubkey(
    h: *const MtPostman,
    out: *mut u8,
    out_cap: usize,
) -> usize {
    if h.is_null() || out.is_null() {
        return 0;
    }
    let pk = (*h).muq().host_kem_pubkey();
    let bytes = pk.as_bytes();
    if bytes.len() > out_cap {
        return 0;
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), out, bytes.len());
    bytes.len()
}

/// Opaque client handle (a live QUIC connection to the postman/courier).
/// `pending` is the tail buffer of a batch fetch: `subscribe_via_courier` returns the ENTIRE queue
/// batch at once (peek does not drop; drop happens on `mt_client_ack`, DEV-049(a) drop-on-ack),
/// so the FFI must keep the whole batch and hand it out one at a time, otherwise items[1..] are lost
/// (§206 "the buffer never loses a message").
pub struct MtClient {
    inner: MuqClient,
    pending: Mutex<VecDeque<QueueItem>>,
}

/// Connect to a postman at address `addr` (host:port). Returns a handle or null.
///
/// # Safety
/// `addr` is a valid C string.
#[no_mangle]
pub unsafe extern "C" fn mt_client_connect(addr: *const c_char) -> *mut MtClient {
    let Some(a) = cstr_to_socketaddr(addr) else {
        return std::ptr::null_mut();
    };
    let Some(rt) = rt() else {
        return std::ptr::null_mut();
    };
    match ffi_catch(|| rt.block_on(MuqClient::connect(a))) {
        Some(Ok(inner)) => Box::into_raw(Box::new(MtClient {
            inner,
            pending: Mutex::new(VecDeque::new()),
        })),
        _ => std::ptr::null_mut(),
    }
}

/// Register a queue on the host `host_overlay` (32 B) via the courier the
/// client is connected to. `host_kem` is the host's 1184 B pubkey; `queue` is a serialized Queue
/// (`queue_len` bytes). Returns 0 on success, -1 on error.
///
/// # Safety
/// `client` is a valid handle; `host_overlay` → 32 B; `host_kem` → 1184 B; `queue` → `queue_len` B.
#[no_mangle]
pub unsafe extern "C" fn mt_client_register(
    client: *const MtClient,
    host_overlay: *const u8,
    host_kem: *const u8,
    queue: *const u8,
    queue_len: usize,
) -> i32 {
    if client.is_null() || host_overlay.is_null() || host_kem.is_null() || queue.is_null() {
        return -1;
    }
    let Some(rt) = rt() else {
        return -1;
    };
    let mut overlay = [0u8; 32];
    std::ptr::copy_nonoverlapping(host_overlay, overlay.as_mut_ptr(), 32);
    let kem_slice = std::slice::from_raw_parts(host_kem, mt_crypto::MLKEM_PUBLIC_KEY_SIZE);
    let Some(kem) = MlkemPublicKey::from_slice(kem_slice) else {
        return -1;
    };
    let q_slice = std::slice::from_raw_parts(queue, queue_len);
    let Ok(q) = Queue::decode(q_slice) else {
        return -1;
    };
    match ffi_catch(|| rt.block_on((*client).inner.register_via_courier(overlay, &kem, &q))) {
        Some(Ok(true)) => 0,
        _ => -1,
    }
}

/// Register a queue DIRECTLY on the connected node (TAG_QUEUE_REGISTER, no courier). Self-host uses
/// this against its OWN node (loopback): the queue registers locally via `handle_register` without any
/// self-connection (the courier path opens a socket to itself, which fails for a self-host node).
/// `queue` is a serialized Queue (`queue_len` bytes). Returns 0 on success, -1 on error.
///
/// # Safety
/// `client` is a valid handle from `mt_client_connect`; `queue` → `queue_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn mt_client_register_direct(
    client: *const MtClient,
    queue: *const u8,
    queue_len: usize,
) -> i32 {
    if client.is_null() || queue.is_null() {
        return -1;
    }
    let Some(rt) = rt() else {
        return -1;
    };
    let q_slice = std::slice::from_raw_parts(queue, queue_len);
    let Ok(q) = Queue::decode(q_slice) else {
        return -1;
    };
    match ffi_catch(|| rt.block_on((*client).inner.register_queue(&q))) {
        Some(Ok(true)) => 0,
        _ => -1,
    }
}

/// Node hello (serverless state machine): connect to node `addr`, obtain its capability —
/// host_kem (1184 B into out_kem) + send_id (32 B into out_send_id). The sender finds the peer's
/// node via mDNS and via hello learns where/how to deposit, without a map. 0=success, -1=error.
///
/// # Safety
/// `addr` — C-string; `out_kem` — 1184 B; `out_send_id` — 32 B.
#[no_mangle]
pub unsafe extern "C" fn mt_node_hello(
    addr: *const c_char,
    out_kem: *mut u8,
    out_send_id: *mut u8,
) -> i32 {
    if addr.is_null() || out_kem.is_null() || out_send_id.is_null() {
        return -1;
    }
    let Some(a) = cstr_to_socketaddr(addr) else {
        return -1;
    };
    let Some(rt) = rt() else {
        return -1;
    };
    match ffi_catch(|| rt.block_on(mt_postman::node_hello(a))) {
        Some(Ok((kem, sid))) => {
            std::ptr::copy_nonoverlapping(kem.as_ptr(), out_kem, 1184);
            std::ptr::copy_nonoverlapping(sid.as_ptr(), out_send_id, 32);
            0
        },
        _ => -1,
    }
}

/// Free the client handle (closes the connection).
///
/// # Safety
/// `c` is a handle from `mt_client_connect` or null; do not reuse.
#[no_mangle]
pub unsafe extern "C" fn mt_client_free(c: *mut MtClient) {
    if !c.is_null() {
        drop(Box::from_raw(c));
    }
}

/// SAFETY helper: build a SecretKey from an FFI pointer (4032 B). None if null.
///
/// # Safety
/// `ptr` is a pointer to `SECRET_KEY_SIZE` bytes or null.
unsafe fn secret_from_ptr(ptr: *const u8) -> Option<SecretKey> {
    if ptr.is_null() {
        return None;
    }
    let mut arr = [0u8; SECRET_KEY_SIZE];
    std::ptr::copy_nonoverlapping(ptr, arr.as_mut_ptr(), SECRET_KEY_SIZE);
    let sk = SecretKey::from_array(arr);
    arr.zeroize(); // [u8; N] is Copy: from_array zeroized its own copy, not our stack remainder
    Some(sk)
}

/// Send message `msg` to queue `send_id` on host `host_overlay` via the courier
/// (two-hop deposit, sealed to the host's ML-KEM). Builds HostDeposit+signature+seal internally.
/// Single shard. Returns 0 on success, -1 on error.
///
/// # Safety
/// `client` is valid; `host_overlay`→32; `host_kem`→1184; `send_id`→32; `send_sk`→4032;
/// `msg_id`→16; `msg`→`msg_len`.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn mt_client_send(
    client: *const MtClient,
    host_overlay: *const u8,
    host_kem: *const u8,
    send_id: *const u8,
    send_sk: *const u8,
    msg_id: *const u8,
    msg: *const u8,
    msg_len: usize,
) -> i32 {
    if client.is_null()
        || host_overlay.is_null()
        || host_kem.is_null()
        || send_id.is_null()
        || msg_id.is_null()
        || msg.is_null()
    {
        return -1;
    }
    let Some(rt) = rt() else {
        return -1;
    };
    let mut overlay = [0u8; 32];
    std::ptr::copy_nonoverlapping(host_overlay, overlay.as_mut_ptr(), 32);
    let kem_slice = std::slice::from_raw_parts(host_kem, mt_crypto::MLKEM_PUBLIC_KEY_SIZE);
    let Some(kem) = MlkemPublicKey::from_slice(kem_slice) else {
        return -1;
    };
    let mut sid = [0u8; 32];
    std::ptr::copy_nonoverlapping(send_id, sid.as_mut_ptr(), 32);
    let Some(sk) = secret_from_ptr(send_sk) else {
        return -1;
    };
    let mut mid = [0u8; 16];
    std::ptr::copy_nonoverlapping(msg_id, mid.as_mut_ptr(), 16);
    let ct = std::slice::from_raw_parts(msg, msg_len).to_vec();

    let mut nonce = [0u8; 16];
    if getrandom::getrandom(&mut nonce).is_err() {
        return -1;
    }
    let Ok(sig) = sign_deposit(&sk, &sid, &mid, &nonce) else {
        return -1;
    };
    let hd = HostDeposit {
        send_id: sid,
        msg_id: mid,
        ttl_windows: 240,
        shard_index: 0,
        shard_total: 1,
        nonce,
        ct,
        sig: *sig.as_bytes(),
    };
    let Ok(sealed) = mt_crypto::seal_to(&kem, &hd.to_bytes()) else {
        return -1;
    };
    let pf = ProxyForward {
        host_addr: overlay,
        sealed,
    };
    match ffi_catch(|| rt.block_on((*client).inner.deposit_via_proxy(&pf))) {
        Some(Ok(true)) => 0,
        _ => -1,
    }
}

/// Fetch one message from queue `recv_id` on host `host_overlay` via the courier.
/// Writes the ct of the first envelope into `out` (capacity `out_cap`), returns its length;
/// 0 if the queue is empty or on error.
///
/// # Safety
/// `client` is valid; `host_overlay`→32; `host_kem`→1184; `recv_id`→32; `recv_sk`→4032;
/// `out`→`out_cap`.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn mt_client_recv(
    client: *const MtClient,
    host_overlay: *const u8,
    host_kem: *const u8,
    recv_id: *const u8,
    recv_sk: *const u8,
    out: *mut u8,
    out_cap: usize,
) -> usize {
    if client.is_null() || out.is_null() {
        return 0;
    }
    // B3: first serve from the tail buffer of the previous batch fetch — items[1..] are not lost.
    // Return: 0 = queue empty; need > out_cap = buffer too small (item retained, reallocate
    // out_cap ≥ need and retry); need ≤ out_cap = need bytes written.
    {
        let mut pending = (*client).pending.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(item) = pending.front() {
            let need = item.ct.len();
            if need > out_cap {
                return need;
            }
            std::ptr::copy_nonoverlapping(item.ct.as_ptr(), out, need);
            pending.pop_front();
            return need;
        }
    }
    // Buffer empty — pull a new batch via the courier: subscribe returns the ENTIRE batch at once
    // (peek — drop only on mt_client_ack, DEV-049(a)), so we keep the whole batch.
    if host_overlay.is_null() || host_kem.is_null() || recv_id.is_null() {
        return 0;
    }
    let Some(rt) = rt() else {
        return 0;
    };
    let mut overlay = [0u8; 32];
    std::ptr::copy_nonoverlapping(host_overlay, overlay.as_mut_ptr(), 32);
    let kem_slice = std::slice::from_raw_parts(host_kem, mt_crypto::MLKEM_PUBLIC_KEY_SIZE);
    let Some(kem) = MlkemPublicKey::from_slice(kem_slice) else {
        return 0;
    };
    let mut rid = [0u8; 32];
    std::ptr::copy_nonoverlapping(recv_id, rid.as_mut_ptr(), 32);
    let Some(sk) = secret_from_ptr(recv_sk) else {
        return 0;
    };
    let Some(Ok(resp)) = ffi_catch(|| {
        rt.block_on(
            (*client)
                .inner
                .subscribe_via_courier(overlay, &kem, rid, &sk),
        )
    }) else {
        return 0;
    };
    if resp.items.is_empty() {
        return 0;
    }
    let mut pending = (*client).pending.lock().unwrap_or_else(|p| p.into_inner());
    pending.extend(resp.items);
    let Some(item) = pending.front() else {
        return 0;
    };
    let need = item.ct.len();
    if need > out_cap {
        return need;
    }
    std::ptr::copy_nonoverlapping(item.ct.as_ptr(), out, need);
    pending.pop_front();
    need
}

/// Acknowledge receipt (DEV-049(a) §593): the host drops the recv_id queue buffer. 0 = success.
///
/// # Safety
/// `client` is valid; `host_overlay`→32; `host_kem`→1184; `recv_id`→32; `recv_sk`→4032.
#[no_mangle]
pub unsafe extern "C" fn mt_client_ack(
    client: *const MtClient,
    host_overlay: *const u8,
    host_kem: *const u8,
    recv_id: *const u8,
    recv_sk: *const u8,
) -> i32 {
    if client.is_null() || host_overlay.is_null() || host_kem.is_null() || recv_id.is_null() {
        return -1;
    }
    let Some(rt) = rt() else {
        return -1;
    };
    let mut overlay = [0u8; 32];
    std::ptr::copy_nonoverlapping(host_overlay, overlay.as_mut_ptr(), 32);
    let kem_slice = std::slice::from_raw_parts(host_kem, mt_crypto::MLKEM_PUBLIC_KEY_SIZE);
    let Some(kem) = MlkemPublicKey::from_slice(kem_slice) else {
        return -1;
    };
    let mut rid = [0u8; 32];
    std::ptr::copy_nonoverlapping(recv_id, rid.as_mut_ptr(), 32);
    let Some(sk) = secret_from_ptr(recv_sk) else {
        return -1;
    };
    match ffi_catch(|| rt.block_on((*client).inner.ack_via_courier(overlay, &kem, rid, &sk))) {
        Some(Ok(true)) => 0,
        _ => -1,
    }
}

/// DEV-049(b): RS(k,n) multi-host send — splits `msg` into `n` shards and deposits
/// one to each of the `n` hosts. Hosts are concatenated arrays: `host_overlays`
/// (n*32), `host_kems` (n*1184). Return: number of successful deposits (durability when >= k),
/// -1 on error.
///
/// # Safety
/// `client` is valid; `host_overlays`→`n*32`; `host_kems`→`n*1184`; `send_id`→32;
/// `send_sk`→4032; `msg_id`→16; `msg`→`msg_len`.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn mt_client_send_erasure(
    client: *const MtClient,
    host_overlays: *const u8,
    host_kems: *const u8,
    n: usize,
    k: usize,
    send_id: *const u8,
    send_sk: *const u8,
    msg_id: *const u8,
    msg: *const u8,
    msg_len: usize,
) -> i32 {
    if client.is_null()
        || host_overlays.is_null()
        || host_kems.is_null()
        || send_id.is_null()
        || msg_id.is_null()
        || msg.is_null()
        || n == 0
    {
        return -1;
    }
    let Some(rt) = rt() else {
        return -1;
    };
    let ksz = mt_crypto::MLKEM_PUBLIC_KEY_SIZE;
    let mut hosts = Vec::with_capacity(n);
    for i in 0..n {
        let mut overlay = [0u8; 32];
        std::ptr::copy_nonoverlapping(host_overlays.add(i * 32), overlay.as_mut_ptr(), 32);
        let kem_slice = std::slice::from_raw_parts(host_kems.add(i * ksz), ksz);
        let Some(kem) = MlkemPublicKey::from_slice(kem_slice) else {
            return -1;
        };
        hosts.push((overlay, kem));
    }
    let mut sid = [0u8; 32];
    std::ptr::copy_nonoverlapping(send_id, sid.as_mut_ptr(), 32);
    let Some(sk) = secret_from_ptr(send_sk) else {
        return -1;
    };
    let mut mid = [0u8; 16];
    std::ptr::copy_nonoverlapping(msg_id, mid.as_mut_ptr(), 16);
    let ct = std::slice::from_raw_parts(msg, msg_len).to_vec();
    match ffi_catch(|| {
        rt.block_on(
            (*client)
                .inner
                .deposit_erasure(&hosts, k, sid, &sk, mid, &ct),
        )
    }) {
        Some(Ok(ok)) if ok >= k => 0,
        _ => -1,
    }
}

/// DEV-049(b): RS(k,n) multi-host fetch — collects shards from `n` hosts and reconstructs
/// from any `k`. Writes the reconstructed ct into `out`; return is the length (0 if fewer than k
/// collected / on error; need > out_cap = buffer too small).
///
/// # Safety
/// `client` is valid; `host_overlays`→`n*32`; `host_kems`→`n*1184`; `recv_id`→32;
/// `recv_sk`→4032; `out`→`out_cap`.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn mt_client_recv_erasure(
    client: *const MtClient,
    host_overlays: *const u8,
    host_kems: *const u8,
    n: usize,
    k: usize,
    recv_id: *const u8,
    recv_sk: *const u8,
    out: *mut u8,
    out_cap: usize,
) -> usize {
    if client.is_null()
        || host_overlays.is_null()
        || host_kems.is_null()
        || recv_id.is_null()
        || out.is_null()
        || n == 0
    {
        return 0;
    }
    let Some(rt) = rt() else {
        return 0;
    };
    let ksz = mt_crypto::MLKEM_PUBLIC_KEY_SIZE;
    let mut hosts = Vec::with_capacity(n);
    for i in 0..n {
        let mut overlay = [0u8; 32];
        std::ptr::copy_nonoverlapping(host_overlays.add(i * 32), overlay.as_mut_ptr(), 32);
        let kem_slice = std::slice::from_raw_parts(host_kems.add(i * ksz), ksz);
        let Some(kem) = MlkemPublicKey::from_slice(kem_slice) else {
            return 0;
        };
        hosts.push((overlay, kem));
    }
    let mut rid = [0u8; 32];
    std::ptr::copy_nonoverlapping(recv_id, rid.as_mut_ptr(), 32);
    let Some(sk) = secret_from_ptr(recv_sk) else {
        return 0;
    };
    match ffi_catch(|| rt.block_on((*client).inner.fetch_erasure(&hosts, k, rid, &sk))) {
        Some(Ok(Some(ct))) => {
            if ct.len() > out_cap {
                return ct.len();
            }
            std::ptr::copy_nonoverlapping(ct.as_ptr(), out, ct.len());
            ct.len()
        },
        _ => 0,
    }
}

impl MtPostman {
    pub(crate) fn muq(&self) -> &Arc<MuqState> {
        &self.muq
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn postman_start_reports_port_and_stops() {
        let bind = CString::new("127.0.0.1:0").unwrap();
        let mut buf = [0u8; 64];
        let h =
            unsafe { mt_postman_start(bind.as_ptr(), buf.as_mut_ptr() as *mut c_char, buf.len()) };
        assert!(!h.is_null(), "postman started");
        let port = unsafe { mt_postman_port(h) };
        assert!(port != 0, "real port assigned");
        // out_addr contains 127.0.0.1:<port>
        let reported = unsafe { CStr::from_ptr(buf.as_ptr() as *const c_char) }
            .to_str()
            .unwrap();
        assert!(
            reported.starts_with("127.0.0.1:"),
            "address recorded: {reported}"
        );
        unsafe { mt_postman_stop(h) };
    }

    #[test]
    fn add_route_ok_and_rejects_bad_args() {
        let bind = CString::new("127.0.0.1:0").unwrap();
        let h = unsafe { mt_postman_start(bind.as_ptr(), std::ptr::null_mut(), 0) };
        assert!(!h.is_null());
        let overlay = [0xA0u8; 32];
        let target = CString::new("127.0.0.1:9999").unwrap();
        assert_eq!(
            unsafe { mt_postman_add_route(h, overlay.as_ptr(), target.as_ptr()) },
            0
        );
        // garbage target → -1
        let bad = CString::new("xxx").unwrap();
        assert_eq!(
            unsafe { mt_postman_add_route(h, overlay.as_ptr(), bad.as_ptr()) },
            -1
        );
        // null handle → -1
        assert_eq!(
            unsafe { mt_postman_add_route(std::ptr::null(), overlay.as_ptr(), target.as_ptr()) },
            -1
        );
        unsafe { mt_postman_stop(h) };
    }

    #[test]
    fn ffi_client_registers_queue_via_courier() {
        use mt_overlay::muq::{derive_queue_keypairs, Queue};
        let loop0 = CString::new("127.0.0.1:0").unwrap();
        // host + courier (FFI)
        let host = unsafe { mt_postman_start(loop0.as_ptr(), std::ptr::null_mut(), 0) };
        let courier = unsafe { mt_postman_start(loop0.as_ptr(), std::ptr::null_mut(), 0) };
        assert!(!host.is_null() && !courier.is_null());
        let host_port = unsafe { mt_postman_port(host) };
        let courier_port = unsafe { mt_postman_port(courier) };
        // route courier → host
        let host_overlay = [0xA0u8; 32];
        let host_addr = CString::new(format!("127.0.0.1:{host_port}")).unwrap();
        assert_eq!(
            unsafe { mt_postman_add_route(courier, host_overlay.as_ptr(), host_addr.as_ptr()) },
            0
        );
        // host's ML-KEM pubkey via FFI
        let mut kem = [0u8; 1184];
        let n = unsafe { mt_postman_kem_pubkey(host, kem.as_mut_ptr(), kem.len()) };
        assert_eq!(n, 1184);
        // client connects to the courier
        let courier_addr = CString::new(format!("127.0.0.1:{courier_port}")).unwrap();
        let client = unsafe { mt_client_connect(courier_addr.as_ptr()) };
        assert!(!client.is_null(), "client connected to courier");
        // build a Queue (ephemeral queue keys)
        let ((recv_pk, _), (send_pk, _)) = derive_queue_keypairs(&[0x42u8; 32], 0).unwrap();
        let q = Queue {
            recv_id: [0x71u8; 32],
            send_id: [0x51u8; 32],
            recv_pubkey: *recv_pk.as_bytes(),
            send_pubkey: Some(*send_pk.as_bytes()),
            rotation_epoch: 1000,
            quota: 64,
        };
        let qb = q.to_bytes();
        // registration via the courier (the host sees the courier, not the client)
        let rc = unsafe {
            mt_client_register(
                client,
                host_overlay.as_ptr(),
                kem.as_ptr(),
                qb.as_ptr(),
                qb.len(),
            )
        };
        assert_eq!(rc, 0, "FFI client registered queue via FFI courier");
        unsafe {
            mt_client_free(client);
            mt_postman_stop(host);
            mt_postman_stop(courier);
        }
    }

    #[test]
    fn ffi_full_message_exchange_a_to_b() {
        use mt_overlay::muq::{derive_queue_keypairs, Queue};
        let loop0 = CString::new("127.0.0.1:0").unwrap();
        let host = unsafe { mt_postman_start(loop0.as_ptr(), std::ptr::null_mut(), 0) };
        let courier = unsafe { mt_postman_start(loop0.as_ptr(), std::ptr::null_mut(), 0) };
        let host_port = unsafe { mt_postman_port(host) };
        let courier_port = unsafe { mt_postman_port(courier) };
        let host_overlay = [0xA0u8; 32];
        let host_addr = CString::new(format!("127.0.0.1:{host_port}")).unwrap();
        unsafe { mt_postman_add_route(courier, host_overlay.as_ptr(), host_addr.as_ptr()) };
        let mut kem = [0u8; 1184];
        unsafe { mt_postman_kem_pubkey(host, kem.as_mut_ptr(), kem.len()) };
        let courier_addr = CString::new(format!("127.0.0.1:{courier_port}")).unwrap();

        // queue keys
        let ((recv_pk, recv_sk), (send_pk, send_sk)) =
            derive_queue_keypairs(&[0x42u8; 32], 0).unwrap();
        let recv_id = [0x71u8; 32];
        let send_id = [0x51u8; 32];
        let q = Queue {
            recv_id,
            send_id,
            recv_pubkey: *recv_pk.as_bytes(),
            send_pubkey: Some(*send_pk.as_bytes()),
            rotation_epoch: 1000,
            quota: 64,
        };
        let qb = q.to_bytes();

        // B registers the queue via the courier
        let b = unsafe { mt_client_connect(courier_addr.as_ptr()) };
        assert_eq!(
            unsafe {
                mt_client_register(
                    b,
                    host_overlay.as_ptr(),
                    kem.as_ptr(),
                    qb.as_ptr(),
                    qb.len(),
                )
            },
            0
        );

        // A sends a message via the courier
        let a = unsafe { mt_client_connect(courier_addr.as_ptr()) };
        let msg = b"privet cherez FFI most";
        let msg_id = [0x5Au8; 16];
        let rc = unsafe {
            mt_client_send(
                a,
                host_overlay.as_ptr(),
                kem.as_ptr(),
                send_id.as_ptr(),
                send_sk.as_bytes().as_ptr(),
                msg_id.as_ptr(),
                msg.as_ptr(),
                msg.len(),
            )
        };
        assert_eq!(rc, 0, "A sent via FFI");

        // B fetches via the courier → byte-for-byte the same message
        let b2 = unsafe { mt_client_connect(courier_addr.as_ptr()) };
        let mut out = [0u8; 256];
        let n = unsafe {
            mt_client_recv(
                b2,
                host_overlay.as_ptr(),
                kem.as_ptr(),
                recv_id.as_ptr(),
                recv_sk.as_bytes().as_ptr(),
                out.as_mut_ptr(),
                out.len(),
            )
        };
        assert_eq!(&out[..n], msg, "B received A message via FFI bridge");

        unsafe {
            mt_client_free(a);
            mt_client_free(b);
            mt_client_free(b2);
            mt_postman_stop(host);
            mt_postman_stop(courier);
        }
    }

    #[test]
    fn ffi_recv_preserves_full_batch() {
        // B3 regression: A sends 3, B fetches 3 — items[1..] are not lost (§206). Before the fix
        // the host dropped the ENTIRE batch while the FFI returned only the first → #2/#3 were lost.
        use mt_overlay::muq::{derive_queue_keypairs, Queue};
        let loop0 = CString::new("127.0.0.1:0").unwrap();
        let host = unsafe { mt_postman_start(loop0.as_ptr(), std::ptr::null_mut(), 0) };
        let courier = unsafe { mt_postman_start(loop0.as_ptr(), std::ptr::null_mut(), 0) };
        let host_port = unsafe { mt_postman_port(host) };
        let courier_port = unsafe { mt_postman_port(courier) };
        let host_overlay = [0xA0u8; 32];
        let host_addr = CString::new(format!("127.0.0.1:{host_port}")).unwrap();
        unsafe { mt_postman_add_route(courier, host_overlay.as_ptr(), host_addr.as_ptr()) };
        let mut kem = [0u8; 1184];
        unsafe { mt_postman_kem_pubkey(host, kem.as_mut_ptr(), kem.len()) };
        let courier_addr = CString::new(format!("127.0.0.1:{courier_port}")).unwrap();

        let ((recv_pk, recv_sk), (send_pk, send_sk)) =
            derive_queue_keypairs(&[0x99u8; 32], 0).unwrap();
        let recv_id = [0x73u8; 32];
        let send_id = [0x53u8; 32];
        let q = Queue {
            recv_id,
            send_id,
            recv_pubkey: *recv_pk.as_bytes(),
            send_pubkey: Some(*send_pk.as_bytes()),
            rotation_epoch: 1000,
            quota: 64,
        };
        let qb = q.to_bytes();
        let b = unsafe { mt_client_connect(courier_addr.as_ptr()) };
        assert_eq!(
            unsafe {
                mt_client_register(
                    b,
                    host_overlay.as_ptr(),
                    kem.as_ptr(),
                    qb.as_ptr(),
                    qb.len(),
                )
            },
            0
        );

        // A sends 3 messages (different msg_id + content)
        let a = unsafe { mt_client_connect(courier_addr.as_ptr()) };
        let msgs: [&[u8]; 3] = [b"soobshenie odin", b"soobshenie dva.", b"soobshenie tri!"];
        for (i, m) in msgs.iter().enumerate() {
            let msg_id = [i as u8; 16];
            let rc = unsafe {
                mt_client_send(
                    a,
                    host_overlay.as_ptr(),
                    kem.as_ptr(),
                    send_id.as_ptr(),
                    send_sk.as_bytes().as_ptr(),
                    msg_id.as_ptr(),
                    m.as_ptr(),
                    m.len(),
                )
            };
            assert_eq!(rc, 0, "A sent #{i}");
        }

        // B fetches — ALL 3 (regression: before the fix it got only #1)
        let b2 = unsafe { mt_client_connect(courier_addr.as_ptr()) };
        let mut got: std::collections::HashSet<Vec<u8>> = std::collections::HashSet::new();
        for _ in 0..3 {
            let mut out = [0u8; 256];
            let n = unsafe {
                mt_client_recv(
                    b2,
                    host_overlay.as_ptr(),
                    kem.as_ptr(),
                    recv_id.as_ptr(),
                    recv_sk.as_bytes().as_ptr(),
                    out.as_mut_ptr(),
                    out.len(),
                )
            };
            assert!(n > 0, "received non-empty envelope");
            got.insert(out[..n].to_vec());
        }
        assert_eq!(got.len(), 3, "all 3 messages received, none lost");
        for m in msgs {
            assert!(got.contains(m), "batch contains message");
        }

        // DEV-049(a): acknowledge receipt — the host drops the queue buffer
        assert_eq!(
            unsafe {
                mt_client_ack(
                    b2,
                    host_overlay.as_ptr(),
                    kem.as_ptr(),
                    recv_id.as_ptr(),
                    recv_sk.as_bytes().as_ptr(),
                )
            },
            0
        );
        // 4th recv — the queue is drained
        let mut out = [0u8; 256];
        let n = unsafe {
            mt_client_recv(
                b2,
                host_overlay.as_ptr(),
                kem.as_ptr(),
                recv_id.as_ptr(),
                recv_sk.as_bytes().as_ptr(),
                out.as_mut_ptr(),
                out.len(),
            )
        };
        assert_eq!(n, 0, "queue empty after draining all");

        unsafe {
            mt_client_free(a);
            mt_client_free(b);
            mt_client_free(b2);
            mt_postman_stop(host);
            mt_postman_stop(courier);
        }
    }

    #[test]
    fn bad_bind_returns_null() {
        let bad = CString::new("not-an-addr").unwrap();
        let h = unsafe { mt_postman_start(bad.as_ptr(), std::ptr::null_mut(), 0) };
        assert!(h.is_null(), "garbage address -> null");
        // null handles are safe
        assert_eq!(unsafe { mt_postman_port(std::ptr::null()) }, 0);
        unsafe { mt_postman_stop(std::ptr::null_mut()) };
    }
}
