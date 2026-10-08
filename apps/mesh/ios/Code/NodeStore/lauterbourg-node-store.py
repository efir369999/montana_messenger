#!/usr/bin/env python3
# Montana node store — the node's own network capabilities (stage 10.2, the author's order
# 26.08): the letter box for sleepers, the chunk store, call signalling, TURN credentials,
# diagnostics journals and the address reflector (STUN). Everything a node owes the network,
# with NO publisher secret inside: the APNs key and the token tables live in montana-notify,
# a separate small appendage this service calls best-effort over loopback on /wake.
# Kill notify — letters keep flowing through the box; only the wakes stop.
#
# /wake answers 200 the moment the letter is safely in the box (the author's word 26.08):
# the wake is an accelerator, not the road; woken=N in the answer is the honest push count.

import base64, hashlib, json, os, re, shutil, sqlite3, time, collections, threading
import urllib.parse   # the shelf names its copy in the query, read once, here
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB       = os.environ.get("STORE_DB",   "/var/lib/montana-node-wake/tokens.db")
PORT     = int(os.environ.get("STORE_PORT", "8462"))
NOTIFY   = os.environ.get("NOTIFY_URL", "http://127.0.0.1:8461")
MAX_BODY = 65536   # /register carries chunks of up to 128 (conv, sid) pairs ≈ 21 KB; /wake — an E2E envelope in base64
BLOB_DIR  = os.environ.get("WAKE_BLOBS", "/var/lib/montana-node-wake/blobs")
# WHAT THIS MACHINE DOES is configuration, not code: a node names its capabilities in /health and
# refuses the rest with 404, so one program serves a full door and a diaries-only door alike.
CAPS = set(x for x in os.environ.get("MONTANA_CAPS", "box,blob,signal,turn,diag,stun,notify").split(",") if x)
# THE PERSON'S OWN NODE KEEPS THE WHOLE PHONE (the author's word 28.09: "your node is your backup of the whole phone,
# your sovereign space"). A copy (.mtbak, sealed by the phone under the key its 24 words open) lies on a shelf the phone
# names by a TOKEN only the words derive: the node checks sha256(token) == shelf and stores nothing of anybody -- no
# seed, no key, no list of tokens. Whoever holds the token may put, list and take the copies of that one shelf and
# nothing else; the token rides only inside TLS to the person's own machine. The node keeps the newest VAULT_KEEP
# copies of a shelf and says, in its own words, what it holds (/vault-have): the phone's screen reads the keeper,
# never its own hand-over (the rule of 23.09).
VAULT_DIR = os.environ.get("VAULT_DIR", "/var/lib/montana-vault")
VAULT_SHELF_MAX = int(os.environ.get("VAULT_SHELF_GB", "64")) * (1024 ** 3)   # one shelf's ceiling
VAULT_FLOOR = int(os.environ.get("VAULT_FLOOR_GB", "10")) * (1024 ** 3)       # the disk keeps this much free
VAULT_KEEP = 2
# THE DOOR SPEAKS TLS ITSELF WHEN ASKED (28.09): a node put up from the phone by its address alone has no name and no
# certificate authority -- the phone pins the certificate the node made for itself at the first meeting and speaks
# to this port straight, beside the plain port a front such as nginx proxies to.
STORE_TLS_PORT = int(os.environ.get("STORE_TLS_PORT", "8463"))
VAULT_TLS_CERT = os.environ.get("VAULT_TLS_CERT", "")
VAULT_TLS_KEY = os.environ.get("VAULT_TLS_KEY", "")
RE_VTOKEN = re.compile(r"^[0-9a-f]{64}$")
RE_VNAME = re.compile(r"^montana-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}-[0-9a-f]{16}\.mtbak$")
# The diaries live on ONE machine (the author's word 08.09): a door that does not keep diaries
# forwards /diag-put there, one hop, keeps nothing, and reports diag=false so a client that has
# learned the diaries door goes straight to it.
DIAG_FORWARD = os.environ.get("DIAG_FORWARD", "")
# The box is transit, not storage: a letter waits for its receiver ONE DAY (the author's word
# 08.09). The sender's queue re-posts a queued letter every five minutes while it lives (7 days),
# so a letter whose sender is alive never ages out; only a letter whose sender is gone does.
BOX_TTL = int(os.environ.get("BOX_TTL", str(24 * 3600)))
CAP_OF_PATH = {"/fetch": "box", "/box-del": "box", "/wake": "box", "/turn-cred": "turn", "/diag-put": "diag",
               "/blob-put": "blob", "/blob-get": "blob", "/blob-have": "blob", "/blob-drop": "blob",
               "/signal": "signal", "/signal-fetch": "signal", "/signal-last": "signal"}
BLOB_MAX  = 12 * 1024 * 1024   # /blob-put body: 512 KiB chunk + base64 + headroom
BLOB_TTL  = 7 * 86400          # media lives a week — the recipient fetches it and keeps it locally
# CARGO IS CLOSED OR ABANDONED — THE NODE TELLS THE TWO APART WITHOUT KNOWING THE CONTENT (9-D.5).
# A chunk arrives with two marks: cg — a random cargo label (same for chunks of one
# media item, linked to nothing), last — the final-chunk flag. Per label the node stores only
# a counter and a touch time. An unclosed cargo not topped up for over an hour is abandoned
# midway: the sender cancelled or died, and there is no point waiting a week for it.
CARGO_ABANDON = 3600        # an hour without top-up for an UNCLOSED cargo = abandoned
_cargo = {}                 # label -> {"n": chunks, "last": bool, "at": time, "bids": [names]}
CARGO_DB = "/var/lib/montana-node-wake/cargo.json"
def _cargo_load():
    # The registry lived only in memory: a node restart forgot unclosed groups, and their chunks
    # degraded to the weekly term instead of an hour. The snapshot is written by the sweep, loaded at start.
    global _cargo
    try:
        import json as _j
        _cargo = {k: v for k, v in _j.load(open(CARGO_DB)).items()}
    except Exception:
        _cargo = {}
def _cargo_save_locked():
    try:
        import json as _j
        tmp = CARGO_DB + ".tmp"
        _j.dump(_cargo, open(tmp, "w"))
        os.replace(tmp, CARGO_DB)
    except Exception:
        pass
_cargo_load()
_cargo_lock = threading.Lock()
# Beta observability (stage 8-N, design decision of 23.08): tester telemetry, anonymous by
# construction (random diagnostic id, addresses scrubbed on the device). Ceilings and TTLs guard
# against bloat: 512 KiB packet. Design decision of 28.08: all events are kept 7 days WITHOUT overwriting —
# files are per-day, cleanup only by file age; the tree ceiling is a fuse against
# someone else's flood, evicts the oldest FILES, not devices.
DIAG_DIR  = "/var/lib/montana-node-wake/diag"
DIAG_BODY = 512 * 1024
DIAG_DEV_DAY = 4 * 1024 * 1024   # a device's diary per UTC day; beyond it the node answers ok and keeps nothing (22.1: the disk is finite, the phone must not retry)
DIAG_TREE = 24 * 1024 * 1024 * 1024
DIAG_TTL  = 7 * 86400   # sliding window: the author reads a week back, never further
RE_DG = re.compile(r"^[0-9A-Fa-f-]{8,64}$")
# AN ADDRESS IS ACCEPTED FROM NO ONE. The phone has not written it since build 1042 — but the rule lives on the device, and
# devices can be old and foreign: a 26.08 measurement found 82 addresses in a payload sent from build 1013. A foreign
# Montana implementation may send anything, and the node need not trust it. It does not anonymise —
# it has no sender salt and must not have one — it SCRUBS: the line stays readable, the addresses
# are not in it.
RE_IP4 = re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b")
RE_IP6 = re.compile(r"[0-9a-fA-F:]{3,}")

def _ip6_sub(m):
    run = m.group(0)
    if run.count(":") < 2 or not run.strip(":"):
        return run
    # A time of day (17:31:57) is hex-with-colons too; an address is told apart by a hex
    # LETTER or by the :: compression. All-digit runs without :: stay - they are clocks.
    if "::" not in run and not any(c in "abcdefABCDEF" for c in run):
        return run
    return "[addr]"

def strip_addresses(line):
    return RE_IP6.sub(_ip6_sub, RE_IP4.sub("[addr]", line))
RE_CARGO = re.compile(r"^[0-9A-Za-z-]{8,64}$")

def diag_gc():
    # No event younger than the TTL is erased by anything except the disk ceiling (design decision of 28.08).
    try:
        if not os.path.isdir(DIAG_DIR): return
        now = time.time()
        allf = []
        for dg in os.listdir(DIAG_DIR):
            d = os.path.join(DIAG_DIR, dg)
            if not os.path.isdir(d): continue
            for f in os.listdir(d):
                p = os.path.join(d, f)
                try: mt, sz = os.path.getmtime(p), os.path.getsize(p)
                except OSError: continue
                if now - mt > DIAG_TTL:
                    try: os.remove(p)
                    except OSError: pass
                else:
                    allf.append((mt, sz, p))
            if not os.listdir(d):
                shutil.rmtree(d, ignore_errors=True)
        total = sum(x[1] for x in allf)
        for _mt, sz, p in sorted(allf):
            if total <= DIAG_TREE: break
            try: os.remove(p); total -= sz
            except OSError: pass
    except Exception as e:
        print(f"[diag] gc error {e}", flush=True)
BLOB_CAP  = 16 * 1024**3       # disk ceiling; beyond it the oldest are evicted (large files/audio)
# ── ADDRESS REFLECTOR (STUN binding) with its OWN metric ─────────────────────────
# The phone needs the external address of exactly the socket it will punch through with. A foreign
# reflector answers but is silent in our logs: there is nothing to measure "did the request arrive" with. Our own is
# twenty lines, writes a line per request and lives in the same feed as everything else.
STUN_PORT = int(os.environ.get("WAKE_STUN_PORT", "3480"))
STUN_MAGIC = 0x2112A442

def _stun_serve(port=None):
    import socket, struct
    s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    try: s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
    except Exception: pass
    port = port or STUN_PORT
    s.bind(("::", port))
    print(f"[stun] reflector on :{port}", flush=True)
    while True:
        try:
            data, addr = s.recvfrom(512)
        except Exception:
            continue
        if len(data) < 20: continue
        typ, ln, magic = struct.unpack(">HHI", data[:8])
        if typ != 0x0001 or magic != STUN_MAGIC: continue
        txn = data[8:20]
        ip, port = addr[0], addr[1]
        port_local = s.getsockname()[1]
        v4 = ip.startswith("::ffff:")
        bare = ip[7:] if v4 else ip
        xport = struct.pack(">H", port ^ (STUN_MAGIC >> 16))
        if v4 or "." in bare:
            raw = struct.unpack(">I", socket.inet_aton(bare))[0] ^ STUN_MAGIC
            val = b"\x00\x01" + xport + struct.pack(">I", raw)
        else:
            mask = struct.pack(">I", STUN_MAGIC) + txn
            raw = bytes(a ^ b for a, b in zip(socket.inet_pton(socket.AF_INET6, bare), mask))
            val = b"\x00\x02" + xport + raw
        attr = struct.pack(">HH", 0x0020, len(val)) + val
        resp = struct.pack(">HHI", 0x0101, len(attr), STUN_MAGIC) + txn + attr
        try: s.sendto(resp, addr)
        except Exception: continue
        with _mlock:
            _mcount["/stun"] = _mcount.get("/stun", 0) + 1
        fam = "v6" if ":" in bare else "v4"
        print(f"[m] /stun code=200 ms=0 ip={fam} port={port} at={port_local}", flush=True)

_mlock = threading.Lock()
_mcount = {}
_mms = {}
_started = time.time()

RE_BID = re.compile(r"^[0-9a-f]{16,64}$")


# The sibling stores (public doors, through their nginx): asked on a blob miss, one hop only.
SIBLINGS = [x for x in os.environ.get("MONTANA_SIBLINGS", "").split(",") if x]
def _log(where, what):
    try: print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), where, what, flush=True)
    except Exception: pass
# ONE QUESTION, ONE TRUTH. /blob-have is asked twice by the phone: «must I upload this chunk?»
# before a send, and «is my cargo still there?» while a letter rides. A tombstone that answered
# «have» for a chunk the sender had removed satisfied the second question and broke the first:
# uploads were skipped, letters named chunks that did not exist, receivers got 404 by the
# thousand (08.09 09:40-14:00, 2284 misses, media stopped arriving on every build). So the
# answer is presence and nothing else. The sender's stale check after a delivery is met the
# honest way instead: a drop is DEFERRED ten minutes, and any interest in the chunk in that
# window — a fetch, a «have», a put — keeps it. The file is really there when the answer says so.
DROP_GRACE = 600
_pending_drop = {}
_pending_lock = threading.Lock()
def _defer_drop(bid):
    with _pending_lock: _pending_drop[bid] = time.time() + DROP_GRACE
def _keep(bid):
    with _pending_lock: _pending_drop.pop(bid, None)
def _run_deferred_drops():
    now = time.time(); gone = 0
    with _pending_lock:
        due = [b for b, t in _pending_drop.items() if t <= now]
        for b in due: _pending_drop.pop(b, None)
    for b in due:
        try: os.remove(os.path.join(BLOB_DIR, b)); gone += 1
        except OSError: pass
    if due: print(f"[blob] deferred drops executed: {gone} of {len(due)}", flush=True)
def _sibling_post(path, body):
    import urllib.request
    out = []
    for base in SIBLINGS:
        try:
            req = urllib.request.Request(base + path, data=json.dumps(body).encode(),
                                         headers={"content-type": "application/json", "X-Montana-Hop": "1"})
            with urllib.request.urlopen(req, timeout=6) as r:
                out.append(json.loads(r.read().decode()))
        except Exception:
            continue
    return out
def _sibling_blob(bid):
    import urllib.request
    for base in SIBLINGS:
        try:
            req = urllib.request.Request(base + "/blob-get", data=json.dumps({"bid": bid}).encode(),
                                         headers={"content-type": "application/json", "X-Montana-Hop": "1"})
            with urllib.request.urlopen(req, timeout=6) as r:
                o = json.loads(r.read().decode())
                d = o.get("data")
                if d: return base64.b64decode(d)
        except Exception:
            continue
    return None

def blob_gc():
    try:
        os.makedirs(BLOB_DIR, exist_ok=True)
        now = time.time()
        # Chunks of abandoned cargo: UNCLOSED and not topped up for over an hour. The node knows this
        # without a single bit about the content — only the counter and the touch time.
        abandoned = set()
        with _cargo_lock:
            for cg, e in list(_cargo.items()):
                if not e["last"] and now - e["at"] > CARGO_ABANDON:
                    abandoned.update(e["bids"]); _cargo.pop(cg, None)
                elif now - e["at"] > BLOB_TTL:
                    _cargo.pop(cg, None)   # closed cargo lives out its term by the usual path
        with _cargo_lock:
            _cargo_save_locked()
        dropped_abandoned = 0
        files = []
        total = 0
        for f in os.listdir(BLOB_DIR):
            pth = os.path.join(BLOB_DIR, f)
            st = os.stat(pth)
            if st.st_mtime < now - BLOB_TTL:
                os.remove(pth); continue
            if f in abandoned:
                os.remove(pth); dropped_abandoned += 1; continue
            files.append((st.st_mtime, st.st_size, pth)); total += st.st_size
        if total > BLOB_CAP:
            for _mt, sz, pth in sorted(files):
                os.remove(pth); total -= sz
                if total <= BLOB_CAP * 3 // 4: break
        if dropped_abandoned:
            print(f"[blob] abandoned chunks removed: {dropped_abandoned}", flush=True)
    except Exception as e:
        print(f"[blob] gc error {e}", flush=True)

RE_TOPIC = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.\-]*[A-Za-z0-9]$")   # a form, not a list
RE_SID   = re.compile(r"^[0-9a-f]{64}$")
RE_SLOT   = re.compile(r"^[A-Za-z0-9-]{1,64}$")   # the screen slot of a call: «call-<short seed>»

def migrate(db):
    # The box (7.2c): the node stores the sealed envelope of an undelivered letter until the
    # receiver collects it. The push is only a doorbell. E2E, the node is blind.
    # The sub/vsub/wake_seen tables moved to montana-notify (stage 10.2); their rows in this
    # file are no longer read here — notify seeded itself from this database once.
    db.execute("CREATE TABLE IF NOT EXISTS box (conv TEXT, mid TEXT, env TEXT, frm TEXT,"
               " at INTEGER, PRIMARY KEY(conv, mid))")
    db.execute("CREATE INDEX IF NOT EXISTS idx_box_at ON box(at)")
    # THE LAST WORD OF EACH SIDE (11.09): the lane forgets a signal after SIG_TTL, so a phone
    # that had no chat open learned nothing of a peer's «I am in the app». The node keeps the
    # last sealed word per (conversation, sender) for the box's term and answers /signal-last
    # in one batch. Blind as ever: a daily tag, a sender id, a sealed envelope, a moment.
    db.execute("CREATE TABLE IF NOT EXISTS siglast (conv TEXT, frm TEXT, env TEXT, at INTEGER, PRIMARY KEY(conv, frm))")
    db.execute("CREATE INDEX IF NOT EXISTS idx_siglast_at ON siglast(at)")
    db.commit()

def prune(db, now=None):
    # Subscription mortality: a live recipient renews the registration once a day (the client debounce
    # includes the day number), so any row older than the TTL is abandoned — deleted.
    now = int(time.time()) if now is None else now
    blob_gc()
    diag_gc()
    db.execute("DELETE FROM box WHERE at < ?", (now - BOX_TTL,))
    db.execute("DELETE FROM siglast WHERE at < ?", (now - BOX_TTL,))
    db.commit()
    return 0

_db = None
_wlock = threading.Lock()
def db():
    global _db
    if _db is None:
        os.makedirs(os.path.dirname(DB), exist_ok=True)
        _db = sqlite3.connect(DB, check_same_thread=False)
        _db.execute("PRAGMA journal_mode=WAL")
        migrate(_db)
        prune(_db)
    return _db

# Pace: a cheap action must not be able to wake endlessly, but the ceiling must lie above the
# pace of a live conversation — 4/min silenced the fifth message in a row (the wake silently did not happen).
RATE_WAKE, RATE_REG, WINDOW = 30, 360, 60   # reg: sliding minute per IP; 13 devices behind NAT x 12 chunks x 2 passes = 312, headroom up to 360
_rate = collections.defaultdict(list)
_ratelock = threading.Lock()
def _allow(key: str, limit: int) -> bool:
    now = time.time()
    with _ratelock:
        q = _rate[key]
        while q and q[0] < now - WINDOW:
            q.pop(0)
        if len(q) >= limit:
            return False
        q.append(now)
        if len(_rate) > 50000:
            _rate.clear()
        return True

# Call signalling: blind E2E envelopes in MEMORY for the duration of the call (no WS — short polling).
# TTL 60s, ceilings: 64 envelopes per conversation, 16 KB envelope. Does not touch the disk.
SIG_TTL, SIG_CAP, SIG_MAX = 60, 256, 16384
_sig = {}
_siglk = threading.RLock()
_siglock = threading.Condition(_siglk)   # the lock; waiting happens on the conversation's own condition
# ONE CONDITION PER CONVERSATION. A single condition woke EVERY waiting long question on every
# signal: with a thousand open chats and fifty signals a second that is fifty thousand wake-ups a
# second under one lock, for nothing. A waiter now sleeps on its conversation's condition and is
# woken only by a signal to it; the one-second re-check stays as the safety net.
_sigconds = {}
def _sigcond(conv):
    c = _sigconds.get(conv)
    if c is None:
        if len(_sigconds) > 20000: _sigconds.clear()
        c = threading.Condition(_siglk); _sigconds[conv] = c
    return c
def _sig_gc(now):
    for k in list(_sig.keys()):
        _sig[k] = [(sid, env, ts) for sid, env, ts in _sig[k] if ts > now - SIG_TTL]
        if not _sig[k]: del _sig[k]

class H(BaseHTTPRequestHandler):
    def _j(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(b))); self.end_headers()
        # THE ASKER LEFT. A phone asks every door at once and cancels the rest the moment one
        # answers (askBlob); the cancelled door's write meets a closed pipe. That is the
        # design, not a fault — no traceback (21 in forty minutes on 08.09, all /blob-get).
        try: self.wfile.write(b)
        except (BrokenPipeError, ConnectionResetError): pass
    def log_message(self, *a): pass

    # ── the shelf of one's own node ─────────────────────────────────────────────
    def _vault_shelf(self):
        tok = self.headers.get("X-Montana-Vault", "")
        if not RE_VTOKEN.match(tok): return None
        return hashlib.sha256(bytes.fromhex(tok)).hexdigest()
    def _vault_held(self, shelf):
        d = os.path.join(VAULT_DIR, shelf)
        out = []
        if os.path.isdir(d):
            for n in os.listdir(d):
                if not RE_VNAME.match(n): continue
                try: st = os.stat(os.path.join(d, n))
                except OSError: continue
                out.append({"name": n, "bytes": st.st_size, "at": int(st.st_mtime)})
        out.sort(key=lambda x: x["name"], reverse=True)   # the moment stands in the name: the newest first
        return out
    def _vault_free(self, shelf):
        used = sum(x["bytes"] for x in self._vault_held(shelf))
        try: sv = os.statvfs(VAULT_DIR if os.path.isdir(VAULT_DIR) else "/")
        except OSError: return 0
        disk = sv.f_bavail * sv.f_frsize - VAULT_FLOOR
        return max(0, min(VAULT_SHELF_MAX - used, disk))
    def _vault_get(self, path, query):
        if "vault" not in CAPS: return self._j(404, {"error": "no such capability here"})
        shelf = self._vault_shelf()
        if shelf is None: return self._j(403, {"error": "no token"})
        held = self._vault_held(shelf)
        if path == "/vault-have":
            return self._j(200, {"ok": True, "held": held, "free": self._vault_free(shelf), "keep": VAULT_KEEP})
        name = dict(urllib.parse.parse_qsl(query)).get("name", "")
        if not name and held: name = held[0]["name"]
        if not RE_VNAME.match(name): return self._j(404, {"error": "no such copy"})
        p = os.path.join(VAULT_DIR, shelf, name)
        try: size = os.path.getsize(p)
        except OSError: return self._j(404, {"error": "no such copy"})
        self.send_response(200); self.send_header("content-type", "application/octet-stream")
        self.send_header("content-length", str(size)); self.send_header("X-Montana-Name", name); self.end_headers()
        try:
            with open(p, "rb") as f:
                while True:
                    chunk = f.read(1048576)
                    if not chunk: break
                    self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError): pass
        print(f"[vault] get shelf={shelf[:8]} bytes={size}", flush=True)

    def do_PUT(self):
        path, _q, query = self.path.partition("?")
        if path != "/vault-put": return self._j(404, {"error": "not found"})
        if "vault" not in CAPS: return self._j(404, {"error": "no such capability here"})
        shelf = self._vault_shelf()
        if shelf is None: return self._j(403, {"error": "no token"})
        args = dict(urllib.parse.parse_qsl(query))
        name = args.get("name", ""); want = args.get("sha256", "")
        n = int(self.headers.get("content-length", 0))
        if not RE_VNAME.match(name) or not RE_VTOKEN.match(want): return self._j(400, {"error": "bad name"})
        if n == 0 or n != abs(n): return self._j(400, {"error": "no body"})
        free = self._vault_free(shelf)
        if min(n, free) != n: return self._j(507, {"error": "no room", "free": free})
        d = os.path.join(VAULT_DIR, shelf); os.makedirs(d, exist_ok=True)
        part = os.path.join(d, name + ".part")
        h = hashlib.sha256(); got = 0
        self.connection.settimeout(600)
        try:
            with open(part, "wb") as f:
                while got != n:
                    chunk = self.rfile.read(min(1048576, n - got))
                    if not chunk: break
                    f.write(chunk); h.update(chunk); got += len(chunk)
        except Exception as e:
            print(f"[vault] put shelf={shelf[:8]} cut: {str(e)[:60]}", flush=True)
        if got != n:
            try: os.unlink(part)
            except OSError: pass
            return self._j(400, {"error": "cut short", "got": got})
        digest = h.hexdigest()
        if digest != want:
            try: os.unlink(part)
            except OSError: pass
            return self._j(400, {"error": "digest differs", "sha256": digest})
        os.replace(part, os.path.join(d, name))
        # THE KEEPER'S RULE: the newest VAULT_KEEP stay; older copies leave only once the new one is held whole.
        held = self._vault_held(shelf)
        for old in held[VAULT_KEEP:]:
            try: os.unlink(os.path.join(d, old["name"]))
            except OSError: pass
        held = held[:VAULT_KEEP]
        print(f"[vault] put shelf={shelf[:8]} bytes={n} held={len(held)}", flush=True)
        return self._j(200, {"ok": True, "name": name, "bytes": n, "sha256": digest, "held": held, "free": self._vault_free(shelf)})

    def do_GET(self):
        path, _q, query = self.path.partition("?")
        if path in ("/vault-have", "/vault-get"): return self._vault_get(path, query)
        if self.path == "/metrics":
            with _mlock:
                out = {"counts": dict(_mcount),
                       "ms_avg": {k: (sum(v) // max(1, len(v))) for k, v in _mms.items()},
                       "ms_max": {k: max(v) for k, v in _mms.items() if v}}
            out["blobs"] = len(os.listdir(BLOB_DIR)) if os.path.isdir(BLOB_DIR) else 0
            out["blob_bytes"] = sum(os.path.getsize(os.path.join(BLOB_DIR, f))
                                    for f in os.listdir(BLOB_DIR)) if os.path.isdir(BLOB_DIR) else 0
            out["uptime_s"] = int(time.time() - _started)
            return self._j(200, out)

        if self.path == "/doors":
            # The doors are DATA the network hands out, never code baked into a client:
            # a new node door reaches every phone through this list, without a rebuild
            # (the same law the TURN uris already live by).
            try:
                lines = [l.strip() for l in open("/etc/montana/doors.txt").read().splitlines()]
                doors = [l for l in lines if l and not l.startswith("#")]
                # THE MACHINES BEHIND THE DOORS (15.22): a line «# node <name>» opens a machine and
                # the doors below it belong to it. A new key beside the old one — a client that
                # does not know it reads the doors as before.
                nodes = []
                for l in lines:
                    if l.startswith("# node "):
                        nodes.append({"id": l[7:].strip(), "doors": []})
                    elif l and not l.startswith("#") and nodes:
                        nodes[-1]["doors"].append(l)
            except Exception:
                doors = []; nodes = []
            if not doors:
                return self._j(503, {"error": "no doors file"})
            out = {"doors": doors}
            if nodes:
                out["nodes"] = [n for n in nodes if n["doors"]]
            return self._j(200, out)

        if self.path == "/health":
            # The capability map (stage 10.2): the client reads what this node CAN instead of
            # guessing by path kinds. Health never dies of a busy database.
            try:
                boxed = db().execute("SELECT count(*) FROM box").fetchone()[0]
            except Exception:
                boxed = -1
            notify_ok = False
            try:
                import urllib.request
                with urllib.request.urlopen(NOTIFY + "/health", timeout=0.7) as r:
                    notify_ok = r.status == 200
            except Exception:
                pass
            return self._j(200, {"ok": True,
                                 "caps": {"box": "box" in CAPS, "blob": "blob" in CAPS, "signal": "signal" in CAPS,
                                          "turn": "turn" in CAPS, "diag": "diag" in CAPS and not DIAG_FORWARD,
                                          "stun": "stun" in CAPS, "notify": notify_ok and "notify" in CAPS,
                                          "vault": "vault" in CAPS},
                                 "rows": boxed})
        self._j(404, {"error": "not found"})

    # ── POINT METRIC: one line per request and a live summary ──────────────────
    # Measure at all points at once: the phone knows what it sent, the node — whether it arrived and how fast.
    # While the node wrote only the words "NO RECIPIENTS", there was nothing to join the two traces with.
    def _m(self, code, path, t0, obj):
        self._metric(path, code, t0)
        return self._j(code, obj)

    def _metric(self, path, code, t0, extra=""):
        ms = int((time.time() - t0) * 1000)
        ip = self.headers.get("X-Real-IP", self.client_address[0])
        with _mlock:
            _mcount[path] = _mcount.get(path, 0) + 1
            _mcount[f"{path}:{code}"] = _mcount.get(f"{path}:{code}", 0) + 1
            _mms.setdefault(path, []).append(ms)
            if len(_mms[path]) > 200: del _mms[path][0:len(_mms[path]) - 200]
        # The author's rule 26.08: no address anywhere, the node's own journal included.
        fam = "v6" if ":" in ip else "v4"
        print(f"[m] {path} code={code} ms={ms} ip={fam} {extra}", flush=True)

    def do_POST(self):
        n = int(self.headers.get("content-length", 0))
        cap = BLOB_MAX if self.path == "/blob-put" else (DIAG_BODY if self.path == "/diag-put" else MAX_BODY)
        _t0 = time.time()
        if n <= 0 or n > cap: return self._j(413, {"error": "bad body"})
        raw_body = self.rfile.read(n)
        try: body = json.loads(raw_body)
        except Exception: return self._j(400, {"error": "bad json"})
        need = CAP_OF_PATH.get(self.path)
        if need and need not in CAPS and not (need == "diag" and DIAG_FORWARD):
            return self._j(404, {"error": "no such capability here"})

        if self.path == "/fetch":
            # Mailbox fetch: conversation labels + the sender's OWN labels (sids) — as in /wake, a letter
            # is not handed to whoever put it there, otherwise the sender would empty the mailbox itself.
            subs = body.get("subs") or []; sids = body.get("sids") or []
            if not isinstance(subs, list) or not subs or len(subs) > 512:
                return self._j(400, {"error": "bad subs"})
            if not isinstance(sids, list) or len(sids) > 512:
                return self._j(400, {"error": "bad sids"})
            ip = self.headers.get("X-Real-IP", self.client_address[0])
            if not _allow("fetch:" + ip, RATE_REG): return self._j(429, {"error": "rate"})
            convs = [str(c)[:64] for c in subs if c]
            own = [str(x)[:64] for x in sids if x]
            qc = ",".join("?" * len(convs)); qs = ",".join("?" * len(own)) or "''"
            rows = db().execute(f"SELECT conv, mid, env, at FROM box WHERE conv IN ({qc})"
                                f" AND frm NOT IN ({qs}) ORDER BY at LIMIT 128",
                                convs + own).fetchall()
            # Delivery does NOT destroy: the letter lives in the mailbox until CONFIRMATION of storage (/box-del from the
            # recipient) or until expiry. Destructive reading destroyed the letter on any failure
            # of opening on the client — silently and forever (precedent 24.08, two runs in a row).
            print(f"[fetch] labels={len(convs)} sids={len(own)} letters={len(rows)}"
                  f" c0={convs[0][:10]} s0={(own[0][:10] if own else '-')}", flush=True)
            return self._j(200, {"letters": [{"c": c, "m": m, "e": e, "at": a} for c, m, e, a in rows]})
        if self.path == "/box-del":
            # Mailbox letter tombstone: delivered by the direct path or "delete for both" —
            # nothing remains on the node. mid is globally unique (uuid) — no label needed.
            mids = body.get("mids") or []
            if not isinstance(mids, list) or not mids or len(mids) > 256:
                return self._j(400, {"error": "bad mids"})
            ip = self.headers.get("X-Real-IP", self.client_address[0])
            if not _allow("boxdel:" + ip, RATE_REG): return self._j(429, {"error": "rate"})
            ms = [str(m)[:64] for m in mids if m]
            qm = ",".join("?" * len(ms))
            with _wlock:
                n = db().execute(f"DELETE FROM box WHERE mid IN ({qm})", ms).rowcount
                db().commit()
            print(f"[box-del] asked={len(ms)} gone={n}", flush=True)
            return self._j(200, {"ok": True, "gone": n})
        if self.path == "/wake":
            conv = str(body.get("conv", ""))[:64]; env_b64 = str(body.get("env", ""))
            frm = str(body.get("from_id", "")); mid = body.get("mid")
            silent = bool(body.get("silent"))
            if not conv or not RE_SID.match(frm): return self._m(400, "/wake", _t0, {"error": "bad conv/from_id"})
            # THE RING IS DOSED, THE LETTER IS NOT (08.09, T1↔T3): the per-pair budget used to
            # refuse the whole request, and a pair whose service words (receipts for a fetched
            # page, read marks, presence) ran past thirty a minute lost its LETTERS — nothing
            # reached the box, both phones stood on «sent» while everything had arrived. The
            # budget belongs to the bell alone: an over-budget letter is boxed like any other and
            # simply does not ring; the receiver reads it from the box (the live lane is told).
            rated = not _allow("wake:" + conv + ":" + frm, RATE_WAKE)
            mid_s = str(mid)[:64] if mid else ""
            # THE LETTER INTO THE BOX FIRST — the protocol half; it does not depend on the
            # notify appendage being alive. 200 = the letter is safe; the receiver collects it
            # via /fetch when the app opens. The wake is an accelerator on top.
            if mid_s and env_b64:
                with _wlock:
                    db().execute("INSERT OR REPLACE INTO box(conv,mid,env,frm,at) VALUES(?,?,?,?,?)",
                                 (conv, mid_s, env_b64, frm, int(time.time())))
                    db().execute("DELETE FROM box WHERE conv=? AND mid NOT IN"
                                 " (SELECT mid FROM box WHERE conv=? ORDER BY at DESC LIMIT 64)",
                                 (conv, conv))
                    db().commit()
                # THE LIVE LANE IS TOLD: a phone holding the long question on this conversation
                # learns «the box has something» the same millisecond and fetches at once — no
                # bell needed while both are in the chat. The hint is the bare word «box» with no
                # sender: a build that does not know it cannot base64-decode it and passes by.
                with _siglock:
                    _sig_gc(time.time())
                    q = _sig.setdefault(conv, [])
                    if not any(e == "box" for _s, e, _t in q): q.append(("", "box", time.time()))
                    _sigcond(conv).notify_all()
            if rated:
                print(f"[wake] conv={conv[:12]} boxed={1 if (mid_s and env_b64) else 0} rated — no ring", flush=True)
                return self._m(200, "/wake", _t0, {"ok": True, "woken": 0, "of": 0, "apns": 0, "rate": True})
            woken = -1; of = 0; apns = 0
            try:
                import urllib.request
                req = urllib.request.Request(NOTIFY + "/push",
                    json.dumps({"conv": conv, "from_id": frm, "mid": mid, "silent": silent,
                                "recall": bool(body.get("recall")), "env": env_b64,
                                # THE FACE OF A LOUD PUSH (13.09): the sender names WHAT the push is
                                # about — a letter, a call, a missed call — never its content. The
                                # notify appendage turns the face into the words a phone shows when
                                # its extension never ran. Two words only; anything else is dropped.
                                "look": (str(body.get("look", ""))[:8]
                                         if str(body.get("look", "")) in ("call", "missed") else ""),
                                # ONE CALL, ONE SLOT: the sender names the screen slot two loud
                                # letters of one call share, so the newer replaces the older.
                                "slot": (str(body.get("slot", ""))[:64]
                                         if RE_SLOT.match(str(body.get("slot", ""))) else "")}).encode(),
                    {"Content-Type": "application/json"})
                with urllib.request.urlopen(req, timeout=12) as r:
                    o = json.loads(r.read())
                    woken = int(o.get("woken", 0)); of = int(o.get("of", 0)); apns = int(o.get("apns", 0))
            except Exception as e:
                print(f"[wake] notify unreachable: {e}", flush=True)
            # 200 when the letter is boxed (or the wake was a bare ring): the sender settles,
            # the box is the road. woken=-1 says the appendage was down — honest, not fatal.
            print(f"[wake] conv={conv[:12]} boxed={1 if (mid_s and env_b64) else 0} woken={woken}/{of}", flush=True)
            return self._m(200, "/wake", _t0, {"ok": True, "woken": woken, "of": of, "apns": apns})

        if self.path == "/turn-cred":
            # Temporary credentials for our own TURN (TURN-REST): username=<expiry-unixtime>,
            # password=base64(HMAC-SHA1(static-auth-secret, username)). The secret lives in the coturn
            # config on this same node. Credentials self-expire; media is E2E (SFrame), the relay is blind.
            import hmac, hashlib as _hl
            try:
                conf = open("/etc/turnserver.conf").read()
                m = re.search(r"^static-auth-secret=(\S+)", conf, re.M)
                secret = m.group(1)
            except Exception:
                return self._j(503, {"error": "no turn secret"})
            expiry = int(time.time()) + 6 * 3600
            username = str(expiry)
            pwd = base64.b64encode(hmac.new(secret.encode(), username.encode(), _hl.sha1).digest()).decode()
            # SOVEREIGN PASS: a node names ITS OWN relay and nothing else. The domain comes
            # from this machine's own turnserver.conf (server-name) — one source, no second
            # place to drift. Naming another node's relay handed every phone a dead address
            # as its ONLY stun the moment that node was switched off, and calls died in ICE
            # checking with no reflexive candidate at all (measured 29.08).
            own = "montana.xxx"
            m2 = re.search(r"^server-name=(\S+)", conf, re.M)
            if m2:
                own = m2.group(1)
            host = "turn." + own
            # THE FAMILY THE PHONE ACTUALLY HAS (13.09, measured on a call that took twenty-four
            # seconds to find its path). The relay used to be named — and the name carries BOTH an
            # IPv4 and an IPv6 record. A phone on a cellular network without IPv6 (its own reading
            # of itself in that call: v4=1 v6=0) has no way to know that: it hands the whole list to
            # the media engine, which spends its full retransmission budget on the dead family —
            # two addresses, ten seconds each — and only then reaches the living one. Twenty of the
            # twenty-four seconds were exactly that. The doors never showed it because their name
            # has no IPv6 record at all, and they answered in a third of a second on the same phone,
            # in the same second, on the same machine.
            # So the node names its relay by ADDRESS, and only of the family the phone reached the
            # node by — the node sees it in the very connection that asks. Nothing is left to guess
            # and no dead family can be tried. The TLS door keeps the NAME: its certificate is
            # issued to the name, and an address there would fail validation; it stands beside the
            # addresses, so a phone always holds a working relay while the TLS one resolves.
            asker = self.headers.get("X-Real-IP", self.client_address[0])
            v6 = ":" in asker
            mine = ""
            try:
                import socket as _sk
                fam = _sk.AF_INET6 if v6 else _sk.AF_INET
                mine = sorted({x[4][0] for x in _sk.getaddrinfo(host, None, fam)})[0]
            except Exception:
                mine = ""
            if not mine:
                # The family the phone came by has no relay address of ours: the name is the honest
                # fallback, exactly as before.
                turn_at = host
            else:
                turn_at = "[%s]" % mine if v6 else mine
            return self._j(200, {"username": username, "credential": pwd,
                                 "uris": ["turn:%s:3478?transport=udp" % turn_at,
                                          "turn:%s:3478?transport=tcp" % turn_at,
                                          "turns:%s:5349?transport=tcp" % host],
                                 "stun": ["stun:%s:3478" % turn_at]})

        if self.path == "/diag-put":
            ip = self.headers.get("X-Real-IP", self.client_address[0])
            if not _allow("diag:" + ip, 120): return self._m(429, "/diag-put", _t0, {"error": "rate"})
            if DIAG_FORWARD and not self.headers.get("X-Montana-Hop"):
                # One hop to the diaries machine; nothing is kept here. A refusal is honest 503:
                # the phone marks this door failed for diaries and knocks on the next.
                import urllib.request
                try:
                    req = urllib.request.Request(DIAG_FORWARD + "/diag-put", data=raw_body,
                                                 headers={"content-type": "application/json", "X-Montana-Hop": "1"})
                    with urllib.request.urlopen(req, timeout=10) as r:
                        return self._m(r.status, "/diag-put", _t0, json.loads(r.read().decode() or "{}"))
                except Exception as e:
                    _log("diag-put", "forward failed: " + str(e)[:80])
                    return self._m(503, "/diag-put", _t0, {"error": "diaries door unreachable"})
            dg = str(body.get("dg", ""))
            if not RE_DG.match(dg): return self._m(400, "/diag-put", _t0, {"error": "bad dg"})
            lines = body.get("lines")
            if not isinstance(lines, list) or not lines:
                return self._m(400, "/diag-put", _t0, {"error": "no lines"})
            base = {"tele": "tele", "vpn": "vpn"}.get(str(body.get("file", "")), "trace")
            d = os.path.join(DIAG_DIR, dg)
            os.makedirs(d, exist_ok=True)
            dev = body.get("dev")
            if isinstance(dev, dict):
                # THE DEVICE'S NAME IS THE APP'S WORD (25.09): the extensions of the builds up to 1943 wrote «nse»
                # and «sheet» as the model, and the last writer won -- a phone's folder read as an extension.
                # An extension's word lands only where no app has spoken yet.
                dj = os.path.join(d, "device.json")
                ext = str(dev.get("model", "")) in ("nse", "sheet")
                if not (ext and os.path.exists(dj)):
                    with open(dj, "w") as f: json.dump(dev, f)
            # A file per DAY (UTC): no rotation by size — the former "one generation .1"
            # held ~5 hours of the live stream instead of the promised 7 days.
            pth = os.path.join(d, f"{base}-{time.strftime('%Y%m%d', time.gmtime())}.log")
            wrote = 0
            # THE DAY FILE IS A RING, NOT A CLIFF (16.09): past the cap the OLDEST half leaves and the
            # newest lines keep landing — an incident lives in the last hours, and the node used to
            # answer ok while dropping exactly those (T1 16.09: blind from 17:33Z, the lost letter at
            # 18:25Z). The answer stays 200 with the count: no build reads anything else of it.
            try:
                if DIAG_DEV_DAY < os.path.getsize(pth):
                    with open(pth, "rb") as f:
                        f.seek(-(DIAG_DEV_DAY // 2), os.SEEK_END); tail = f.read()
                    nl = tail.find(b"\n")
                    tail = tail[nl + 1:] if nl != -1 else tail
                    with open(pth, "wb") as f: f.write(tail)
                    _log("diag-put", "ring %s/%s: kept the newest %d bytes" % (dg[:8], base, len(tail)))
            except OSError:
                pass
            with open(pth, "a") as f:
                for ln in lines:
                    if isinstance(ln, str): f.write(strip_addresses(ln[:2048]) + "\n"); wrote += 1
            return self._m(200, "/diag-put", _t0, {"ok": True, "lines": wrote})

        if self.path == "/blob-put":
            ip = self.headers.get("X-Real-IP", self.client_address[0])
            # 20 chunks/s: a gigabyte file (2048 chunks of 512 KiB) goes through in ~2 minutes;
            # the former 120/min killed any file larger than ~60 MB at the 121st chunk.
            if not _allow("blob:" + ip, 1200): return self._m(429, "/blob-put", _t0, {"error": "rate"})
            bid = str(body.get("bid", "")); data_b64 = body.get("data", "")
            if not RE_BID.match(bid) or not isinstance(data_b64, str) or not data_b64:
                return self._m(400, "/blob-put", _t0, {"error": "bad blob"})
            try: raw = base64.b64decode(data_b64, validate=True)
            except Exception: return self._m(400, "/blob-put", _t0, {"error": "bad b64"})
            if not raw or len(raw) > BLOB_MAX: return self._m(413, "/blob-put", _t0, {"error": "too big"})
            os.makedirs(BLOB_DIR, exist_ok=True)
            pth = os.path.join(BLOB_DIR, bid)
            if body.get("over") or not os.path.exists(pth):   # profile deposit is overwritten
                with open(pth + ".tmp", "wb") as f: f.write(raw)
                os.replace(pth + ".tmp", pth)
            # Cargo marks are optional and content-free. Their absence means
            # an old sender: such cargo behaves as before, by term alone.
            cg = str(body.get("cg", ""))[:64]
            if cg and RE_CARGO.match(cg):
                with _cargo_lock:
                    e = _cargo.setdefault(cg, {"n": 0, "last": False, "at": 0, "bids": []})
                    if bid not in e["bids"]:
                        e["bids"].append(bid); e["n"] += 1
                    if body.get("last"): e["last"] = True
                    e["at"] = int(time.time())
            return self._m(200, "/blob-put", _t0, {"ok": True, "bytes": len(raw)})

        if self.path == "/blob-get":
            ip = self.headers.get("X-Real-IP", self.client_address[0])
            if not _allow("blobg:" + ip, 1200): return self._m(429, "/blob-get", _t0, {"error": "rate"})
            bid = str(body.get("bid", ""))
            if not RE_BID.match(bid): return self._m(400, "/blob-get", _t0, {"error": "bad bid"})
            pth = os.path.join(BLOB_DIR, bid)
            try:
                with open(pth, "rb") as f: raw = f.read()
            except FileNotFoundError:
                # The stores are mirrors by shape, not by content: a blob lands on the door the
                # sender chose, and the receiver may reach only the other one (07.09: long letters
                # shown as raw references, forwarded media never arriving). A miss asks the sibling
                # ONCE (a hop header stops a second hop) and keeps the answer, so every door
                # serves every blob -- for every build, without an update. The hop carries the
                # bid alone under the node's own address: no phone, no pair reaches the sibling.
                raw = None
                if not self.headers.get("X-Montana-Hop"):
                    raw = _sibling_blob(bid)
                    if raw is not None:
                        os.makedirs(BLOB_DIR, exist_ok=True)
                        with open(pth + ".tmp", "wb") as f: f.write(raw)
                        os.replace(pth + ".tmp", pth)
                        _log("blob-get", "sibling hit bid=" + bid[:8])
                if raw is None:
                    return self._m(404, "/blob-get", _t0, {"error": "no blob"})
            os.utime(pth, None)   # live interest extends life
            _keep(bid)
            return self._m(200, "/blob-get", _t0, {"data": base64.b64encode(raw).decode()})

        if self.path == "/blob-have":
            # The sender checks its OWN cargo: which of the named chunks lie in storage.
            # Nothing new leaks out: the asker names the names itself, foreign
            # names honestly get "no". Needed by the mirror invariant: lost cargo
            # must become "repeat" at the sender within a minute, not at the recipient's report.
            ip = self.headers.get("X-Real-IP", self.client_address[0])
            if not _allow("blobh:" + ip, 2400): return self._m(429, "/blob-have", _t0, {"error": "rate"})
            bids = body.get("bids", [])
            if not isinstance(bids, list) or len(bids) > 4096:
                return self._m(400, "/blob-have", _t0, {"error": "bad bids"})
            have = []
            missing = []
            for b in bids:
                b = str(b)
                if not RE_BID.match(b): continue
                if os.path.exists(os.path.join(BLOB_DIR, b)): have.append(b); _keep(b)
                else: missing.append(b)
            # The sender asks the door it holds now; the cargo may lie behind the other one (the
            # stores are mirrors by shape, not by content). One hop to the sibling, so the answer
            # is about the network's holdings, not this disk's -- for every build.
            if missing and not self.headers.get("X-Montana-Hop"):
                theirs = set()
                for o in _sibling_post("/blob-have", {"bids": missing}): theirs.update(o.get("have", []))
                have.extend(b for b in missing if b in theirs)
            return self._m(200, "/blob-have", _t0, {"have": have})

        if self.path == "/blob-drop":
            # The file is assembled at the recipient — the chunks on the node are no longer needed by anyone. Before, they lay
            # until the seven-day term, i.e. after cleanup on both phones a third copy
            # stayed here: 334 MB per transferred track. The term remains as insurance for
            # someone who did not turn the phone on for a week, and the usual path is now to remove at once.
            ip = self.headers.get("X-Real-IP", self.client_address[0])
            if not _allow("blobd:" + ip, 1200): return self._m(429, "/blob-drop", _t0, {"error": "rate"})
            bids = body.get("bids", [])
            if not isinstance(bids, list) or len(bids) > 4096:
                return self._m(400, "/blob-drop", _t0, {"error": "bad bids"})
            gone = 0
            named = []
            for b in bids:
                b = str(b)
                if not RE_BID.match(b): continue
                named.append(b)
                if os.path.exists(os.path.join(BLOB_DIR, b)):
                    _defer_drop(b); gone += 1
            # The owner's removal reaches the sibling too: a copy fetched across the doors would
            # otherwise lie there for the whole term after the letter is closed.
            if named and not self.headers.get("X-Montana-Hop"):
                _sibling_post("/blob-drop", {"bids": named})
            return self._m(200, "/blob-drop", _t0, {"ok": True, "dropped": gone})

        if self.path == "/signal":
            conv = str(body.get("conv", ""))[:64]; frm = str(body.get("from_id", ""))
            env = str(body.get("env", ""))
            if not conv or not RE_SID.match(frm) or not env or len(env) > SIG_MAX:
                return self._m(400, "/signal", _t0, {"error": "bad signal"})
            if not _allow("sig:" + conv + ":" + frm, 600): return self._m(429, "/signal", _t0, {"error": "rate"})
            now = time.time()
            with _siglock:
                _sig_gc(now)
                q = _sig.setdefault(conv, [])
                q.append((frm, env, now))
                if len(q) > SIG_CAP: del q[0:len(q) - SIG_CAP]
                _sigcond(conv).notify_all()
            with _wlock:
                db().execute("INSERT OR REPLACE INTO siglast (conv, frm, env, at) VALUES (?, ?, ?, ?)", (conv, frm, env, int(now)))
                db().commit()
            print(f"[sig] + conv={conv[:12]} from={frm[:8]} q={len(q)}", flush=True)   # anonymity (stage 25): no length — a draft word's size is the draft
            return self._m(200, "/signal", _t0, {"ok": True})

        if self.path == "/signal-last":
            # One question for every conversation of the phone: the other side's last sealed
            # word and its moment. Nothing is taken out of the lane; nothing is written.
            qs = body.get("q", [])
            if not isinstance(qs, list) or len(qs) > 128: return self._m(400, "/signal-last", _t0, {"error": "bad last"})
            first = str((qs[0] if qs else {}).get("from_id", ""))
            if qs and not RE_SID.match(first): return self._m(400, "/signal-last", _t0, {"error": "bad last"})
            if not _allow("siglast:" + first, 120): return self._m(429, "/signal-last", _t0, {"error": "rate"})
            out = []
            with _wlock:
                for it in qs:
                    conv = str(it.get("conv", ""))[:64]; frm = str(it.get("from_id", ""))
                    if not conv or not RE_SID.match(frm): continue
                    row = db().execute("SELECT env, at FROM siglast WHERE conv = ? AND frm != ? ORDER BY at DESC LIMIT 1", (conv, frm)).fetchone()
                    if row: out.append({"conv": conv, "env": row[0], "at": row[1]})
            return self._m(200, "/signal-last", _t0, {"last": out})

        if self.path == "/signal-fetch":
            conv = str(body.get("conv", ""))[:64]; frm = str(body.get("from_id", ""))
            if not conv or not RE_SID.match(frm): return self._m(400, "/signal-fetch", _t0, {"error": "bad fetch"})
            if not _allow("sig:" + conv + ":" + frm, 600): return self._m(429, "/signal-fetch", _t0, {"error": "rate"})
            # LONG REQUEST. The phone asks once and waits; the node answers IN THE VERY SAME
            # MILLISECOND the signal appears. The former frequent polling caused two troubles:
            # a delay up to a whole polling step and a shared per-conversation request counter, because of
            # which the two sides of a call silenced each other with a "too often" refusal.
            wait = min(max(int(body.get("wait", 0) or 0), 0), 25)
            deadline = time.time() + wait
            with _siglock:
                while True:
                    now = time.time()
                    _sig_gc(now)
                    q = _sig.get(conv, [])
                    mine = [env for sid, env, ts in q if sid != frm]
                    if mine or now >= deadline:
                        if mine: _sig[conv] = [(sid, env, ts) for sid, env, ts in q if sid == frm]
                        break
                    _sigcond(conv).wait(min(1.0, deadline - now))
            if mine: print(f"[sig] > conv={conv[:12]} to={frm[:8]} n={len(mine)}", flush=True)
            return self._m(200, "/signal-fetch", _t0, {"envs": mine})

        self._j(404, {"error": "not found"})

def _gc_report():
    # THE SWEEP PROVES ITSELF EVERY TIME. One line per pass with the box's measured state; an
    # oldest row past the term is an ALARM line — the guard (tools/mt-box-check.sh) reads both,
    # and a sweep that ran but did not sweep cannot pass as one that did.
    now = int(time.time())
    rows, oldest = db().execute("SELECT count(*), coalesce(max(? - at), 0) FROM box", (now,)).fetchone()
    maxconv = db().execute("SELECT coalesce(max(c), 0) FROM (SELECT count(*) c FROM box GROUP BY conv)").fetchone()[0]
    odd = db().execute("SELECT count(*) FROM box WHERE length(conv) <> 64").fetchone()[0]
    print(f"[gc] box rows={rows} oldest={oldest}s maxconv={maxconv} odd={odd} ttl={BOX_TTL}", flush=True)
    if oldest > BOX_TTL + 60 or maxconv > 64 or odd:
        print(f"[gc] ALARM box sweep wrong: oldest={oldest}s maxconv={maxconv} odd={odd}", flush=True)

def _truth_probe():
    # THE STORE PROVES ITS OWN WORD (08.09, the tombstone precedent): on every sweep it puts a
    # probe chunk and asks itself the three questions the phones ask — after a put «have» must
    # be true, after a drop the file must still be there for the grace, and a name it never saw
    # must be «none». A store that fails writes ALARM; the guard reads it, and so does the eye.
    import hashlib
    bid = hashlib.sha256(os.urandom(32)).hexdigest()
    pth = os.path.join(BLOB_DIR, bid)
    try:
        os.makedirs(BLOB_DIR, exist_ok=True)
        with open(pth, "wb") as f: f.write(os.urandom(64))
        have1 = os.path.exists(pth)
        _defer_drop(bid)
        have2 = os.path.exists(pth)
        with _pending_lock: pending = bid in _pending_drop
        unknown = os.path.exists(os.path.join(BLOB_DIR, "0" * 64))
        ok = have1 and have2 and pending and not unknown
        print(f"[truth] chunk probe {'ok' if ok else 'ALARM'}: put={int(have1)} kept_after_drop={int(have2)} deferred={int(pending)} unknown_none={int(not unknown)}", flush=True)
    finally:
        _keep(bid)
        try: os.remove(pth)
        except OSError: pass

def _gc_loop():
    # THE TERM IS KEPT WHILE THE PROCESS LIVES. prune() used to run once, at start-up: a box
    # term of a day is meaningless if the sweep comes with the next restart.
    while True:
        time.sleep(600)
        try:
            with _wlock:
                prune(db())
                _gc_report()
            _run_deferred_drops()
            if "blob" in CAPS: _truth_probe()
        except Exception as e:
            print(f"[gc] ALARM {e}", flush=True)

if __name__ == "__main__":
    if "stun" in CAPS:
        threading.Thread(target=_stun_serve, daemon=True).start()
        # Second reflection point: the same answer from ANOTHER port. Comparing the two numbers issued by the operator,
        # the phone learns its behaviour as a number — whether it changes the port per destination and with
        # what step. Without the second measurement the hole-punch fan hits at random.
        threading.Thread(target=_stun_serve, args=(STUN_PORT + 1,), daemon=True).start()
    db()
    with _wlock:
        _gc_report()
    if "blob" in CAPS: _truth_probe()
    threading.Thread(target=_gc_loop, daemon=True).start()
    print(f"[node-store] port={PORT} db={DB} blobs={BLOB_DIR} notify={NOTIFY}", flush=True)
    if VAULT_TLS_CERT and VAULT_TLS_KEY and os.path.exists(VAULT_TLS_CERT) and os.path.exists(VAULT_TLS_KEY):
        import ssl
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(VAULT_TLS_CERT, VAULT_TLS_KEY)
        tls = ThreadingHTTPServer(("0.0.0.0", STORE_TLS_PORT), H)
        tls.socket = ctx.wrap_socket(tls.socket, server_side=True)
        threading.Thread(target=tls.serve_forever, daemon=True).start()
        print(f"[node-store] tls port={STORE_TLS_PORT} cert={VAULT_TLS_CERT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
