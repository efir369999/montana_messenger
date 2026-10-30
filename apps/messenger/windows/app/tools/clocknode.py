# A CHECK'S OWN NODE ON A CLOCK OF ITS OWN (the owner's word 25.10.2026 10:5x, chain №910–920: the checks move time by managed clocks
# or isolated rooms, never the computer's date, never a real wallet): the original's own door, apps/messenger/ios/Code/Node/
# montana-home-node.py, run with its clock the real one plus the days written in DIR/shift_days (read at every look, so a check
# moves it while the node runs: the box's minute, the Date header, the week of the blobs), its files under DIR instead of /var/lib and
# /etc/montana, the loopback alone, and only the box, the blobs and the signals (no STUN ports, no TURN, no diaries, no wake pushes).
# THE LIVE BOX, AS DESCRIBED, NOT AS RUN (PR #13, the chairman 25.10.2026 08:16 UTC): the live nodes run montana-node-store.py, not this
# file, and their box marks a letter taken per device (iOS 2306) -- /fetch reads «devs» (the device's name per label) and hands no
# letter to a device that marked it taken under that label; /box-del takes «taken» pairs [mid, device] into a table keyed by both,
# the letter staying for the others until the box's term, and «mids» still buries for everyone. This file's box has none of it, so
# the wrapper adds exactly that behaviour on top; the live code itself is not published.
# Clients reach it only in a check's run: Windows by MONTANA_TEST_DOOR=http://127.0.0.1:PORT (doors::test_door), the emulator by
# 10.0.2.2:PORT. Nothing of the network is touched.
# usage: python3 -I app/tools/clocknode.py NODE_PY DIR [PORT]
import os
import sys
import time

node, root = sys.argv[1], os.path.abspath(sys.argv[2])
port = sys.argv[3] if len(sys.argv) > 3 else "8462"
home = root.replace("\\", "/")
for d in ("montana-node-wake/blobs", "montana-node-wake/diag", "montana-vault", "etc"):
    os.makedirs(os.path.join(root, d), exist_ok=True)
shift_file = os.path.join(root, "shift_days")
_real = time.time
_seen = [0.0, None]


def _shift():
    # the days ahead, as the check wrote them last; a file not there is the real day
    try:
        m = os.path.getmtime(shift_file)
        if m != _seen[1]:
            with open(shift_file, encoding="utf-8") as f:
                _seen[0] = float(f.read().strip() or 0)
            _seen[1] = m
    except (OSError, ValueError):
        _seen[0], _seen[1] = 0.0, None
    return _seen[0]


# the live box's 2306 marks (as described): kept in this node's own database, pruned after the box's term
LIVE_BOX = '''
def _live_taken_table():
    db().execute("CREATE TABLE IF NOT EXISTS taken (mid TEXT, dev TEXT, at INTEGER, PRIMARY KEY(mid, dev))")

def _live_taken(pairs):
    if not isinstance(pairs, list) or not pairs or len(pairs) > 256:
        return None
    rows = []
    for p in pairs:
        if not (isinstance(p, list) and len(p) == 2 and isinstance(p[0], str) and p[0] and isinstance(p[1], str)
                and re.fullmatch(r"[0-9a-f]{64}", p[1])):
            return None
        rows.append((p[0][:64], p[1], int(time.time())))
    with _wlock:
        _live_taken_table()
        db().executemany("INSERT OR IGNORE INTO taken(mid, dev, at) VALUES(?,?,?)", rows)
        db().execute("DELETE FROM taken WHERE at < ? OR mid NOT IN (SELECT mid FROM box)", (int(time.time()) - BOX_TTL,))
        db().commit()
    return len(rows)

def _live_untaken(body, subs, rows, who=""):
    if os.environ.get("CLOCKNODE_DEBUG"):
        boxed = {r[0] for r in db().execute("SELECT DISTINCT conv FROM box").fetchall()}
        asked = {str(c)[:64] for c in subs}
        print(f"[clock] fetch by={who[:24]!r} labels={len(asked)} boxed_convs={len(boxed)} matched={sorted(c[:8] for c in asked & boxed)}"
              f" rows={[(c[:8], m[:14]) for c, m, e, a in rows][:6]} devs={'yes' if body.get('devs') else 'no'} day_now={int(time.time() // 86400)}", flush=True)
    devs = body.get("devs")
    if not isinstance(devs, list) or len(devs) != len(subs):
        return list(rows)   # a page without «devs» reads as before
    dev_of = {str(c)[:64]: str(d) for c, d in zip(subs, devs)}
    _live_taken_table()
    out = [(c, m, e, a) for c, m, e, a in rows
           if not (dev_of.get(c) and db().execute("SELECT 1 FROM taken WHERE mid=? AND dev=?", (m, dev_of[c])).fetchone())]
    if os.environ.get("CLOCKNODE_DEBUG") and len(out) != len(rows):
        print(f"[clock]   after the taken marks: {[(c[:8], m[:14]) for c, m, e, a in out][:6]}", flush=True)
    return out
'''

time.time = lambda: _real() + _shift() * 86400
os.environ["STORE_PORT"] = port
os.environ["MONTANA_CAPS"] = "box,blob,signal"
for k in ("VAULT_TLS_CERT", "VAULT_TLS_KEY", "COIN_REPLICA_FILE", "DIAG_FORWARD"):
    os.environ.pop(k, None)
with open(node, encoding="utf-8") as f:
    src = f.read()
src = src.replace("/var/lib/", home + "/").replace("/etc/montana/", home + "/etc/").replace('"0.0.0.0"', '"127.0.0.1"')


def patch(a, b):
    global src
    if src.count(a) != 1:
        sys.exit(f"[clocknode] the node file differs from the one this wrapper knows: {a[:60]!r}")
    src = src.replace(a, b)


patch('''f" AND frm NOT IN ({qs}) ORDER BY at LIMIT 128",
                                convs + own).fetchall()''',
      '''f" AND frm NOT IN ({qs}) ORDER BY at",
                                convs + own).fetchall()
            rows = _live_untaken(body, subs, rows, self.headers.get("User-Agent", ""))[:128]''')
patch('''            mids = body.get("mids") or []
            if not isinstance(mids, list) or not mids or len(mids) > 256:
                return self._j(400, {"error": "bad mids"})''',
      '''            took = 0
            if "taken" in body:
                took = _live_taken(body.get("taken"))
                if os.environ.get("CLOCKNODE_DEBUG"):
                    print(f"[clock] taken by={self.headers.get('User-Agent', '')[:24]!r} {[(m[:14], d[:8]) for m, d in (body.get('taken') or [])][:6]} -> {took}", flush=True)
                if took is None:
                    return self._j(400, {"error": "bad taken"})
                if not body.get("mids"):
                    return self._j(200, {"ok": True, "gone": 0, "taken": took})
            mids = body.get("mids") or []
            if not isinstance(mids, list) or not mids or len(mids) > 256:
                return self._j(400, {"error": "bad mids"})''')
patch('''if __name__ == "__main__":''', LIVE_BOX + '''
if __name__ == "__main__":''')
print(f"[clocknode] {node} on 127.0.0.1:{port}, files under {root}, clock + {_shift()} days, the live box's 2306 marks", flush=True)
sys.argv = [node]
exec(compile(src, node, "exec"), {"__name__": "__main__", "__file__": node})
