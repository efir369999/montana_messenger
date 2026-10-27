#!/usr/bin/env python3
# The full network run of Protocol-13 item 13 (issue #24), as code. RUN.md beside this file is the
# description; this is what carries it out. Standard library only. Every remote command is an
# argument list run by a small executor on the far host (REMOTE below), reached over ssh with an
# argument list here, so no shell on either side parses a value of the run.
#
# Our own reproduction on our own servers, with the author's permission. It is not an independent
# external audit and nothing it writes may call it one.
#
#   python3 run.py --dry-run                      every command printed, nothing run, exit 0
#   python3 run.py --commit <40 hex> [--run-id ID] the run; exit 0 only if every expectation held
#   python3 run.py --teardown --run-id ID         stop the run's units, remove its namespaces
#
# Exit codes: 0 every expectation held; 1 an expectation failed; 2 the run could not be carried out
# (a refused configuration, an unreachable host, a missing prerequisite).

import argparse
import base64
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))

# Of the tree, file and line in RUN.md, Gate -1.
DECIDED_LEN = 750                 # mt-state/src/lib.rs:39
PROPOSAL_DOMAIN = b"mt-proposal\x00"  # mt-codec/src/lib.rs:88-94, :254
QUORUM = (67, 100)                # mt-genesis/src/lib.rs:91, compared by multiplying (mt-pulse/src/close.rs:20-31)
RETAINED = 8                      # mt-genesis/src/lib.rs:114
MARKS_LEN = 18                    # two marks of one byte and eight (mt-store/src/lib.rs:601, :934-958)

# Lauterbourg-3 carries Kani by the author's word, and the live cohort net4 keeps its store under
# /opt/montana-core on Moscow, Amsterdam and Lauterbourg: the run touches neither.
REFUSED_HOSTS = ("montana-lauterbourg-3",)
REFUSED_DATA = "/opt/montana-core"

# The fields of a proposal up to the cement, in the order and widths of mt-state/src/layout.rs:475-513.
FIELDS = [
    ("window", 8), ("protocol_version", 4), ("previous", 32), ("note_root", 32),
    ("nullifier_root", 32), ("record_root", 32), ("machine_root", 32), ("admitted_root", 32),
    ("credited_root", 32), ("operations_root", 32), ("roll", 32), ("admitted_count", 8),
    ("cement_aggregate", 32), ("cement_count", 8),
]
ROOTS = ("note_root", "nullifier_root", "record_root", "machine_root", "admitted_root",
         "credited_root", "operations_root")

CLOSED_LINE = re.compile(r"window (\d+) closed after .*the next links to the proposal ([0-9a-f]{64})")
FINAL_LINE = re.compile(r"window (\d+) is final under the proposal ([0-9a-f]{64})")
WALKED_LINE = re.compile(r"walked from window (\d+) to the head at window (\d+)")

# The executor on the far host: reads a list of operations and answers one JSON line. It reads a
# store and never writes one: of `window` it reads the two marks alone, since the rest of that
# record carries the machine's standing and is read as a secret (mt-store/src/lib.rs:644-658); it
# never opens `identity`; of `points` and `agreement-*` it reports names and sizes.
REMOTE = r'''
import base64, hashlib, json, os, subprocess
req = json.loads(DATA)
out = []
def marks(data):
    try:
        with open(os.path.join(data, "window"), "rb") as f:
            lead = f.read(18)
    except FileNotFoundError:
        return {"head": None, "closed": None}
    got, at = [], 0
    for _ in range(2):
        if at >= len(lead):
            return {"unreadable": lead.hex()}
        if lead[at] == 0:
            got.append(None); at += 1
        elif lead[at] == 1 and at + 9 <= len(lead):
            got.append(int.from_bytes(lead[at + 1:at + 9], "little")); at += 9
        else:
            return {"unreadable": lead.hex()}
    return {"head": got[0], "closed": got[1]}
def active(unit):
    if not unit:
        return None
    return subprocess.run(["systemctl", "is-active", unit], capture_output=True, text=True).stdout.strip()
for op in req["ops"]:
    kind = op["op"]
    if kind == "run":
        try:
            r = subprocess.run(op["argv"], cwd=op.get("cwd"), capture_output=True, timeout=op.get("timeout", 120))
            out.append({"rc": r.returncode, "out": r.stdout.decode(errors="replace")[-65536:], "err": r.stderr.decode(errors="replace")[-16384:]})
        except subprocess.TimeoutExpired as e:
            out.append({"rc": None, "timeout": True, "out": (e.stdout or b"").decode(errors="replace")[-65536:], "err": (e.stderr or b"").decode(errors="replace")[-16384:]})
        except OSError as e:
            out.append({"rc": None, "err": str(e)})
    elif kind == "marks":
        m = marks(op["data"]); m["active"] = active(op.get("unit")); out.append(m)
    elif kind == "snapshot":
        data, known = op["data"], set(op.get("known", []))
        got = {"marks": marks(data), "active": active(op.get("unit")), "proposals": {}, "agreements": [], "points": {"files": 0, "bytes": 0}}
        at = os.path.join(data, "proposals")
        for name in (sorted(os.listdir(at)) if os.path.isdir(at) else []):
            if len(name) != 20 or not name.isdigit():
                continue  # a temporary of a writing, which no reader reads (mt-store/src/lib.rs:226-229)
            with open(os.path.join(at, name), "rb") as f:
                b = f.read()
            sha = hashlib.sha256(b).hexdigest()
            one = {"sha256": sha, "size": len(b)}
            if sha not in known:
                one["b64"] = base64.b64encode(b).decode()
            got["proposals"][name] = one
        for name in (sorted(os.listdir(data)) if os.path.isdir(data) else []):
            if name.startswith("agreement-"):
                got["agreements"].append([name, os.path.getsize(os.path.join(data, name))])
        for top, _, files in os.walk(os.path.join(data, "points")):
            for name in files:
                got["points"]["files"] += 1
                got["points"]["bytes"] += os.path.getsize(os.path.join(top, name))
        log, offset = op.get("log"), op.get("offset", 0)
        if log and os.path.exists(log):
            with open(log, "rb") as f:
                f.seek(offset)
                chunk = f.read(64 << 20)
            got["log"] = {"from": offset, "b64": base64.b64encode(chunk).decode()}
        if op.get("status"):
            r = subprocess.run(op["status"], capture_output=True, text=True, timeout=60)
            got["status"] = {"rc": r.returncode, "out": (r.stdout + r.stderr).strip()[-4000:]}
        out.append(got)
    elif kind == "put":
        os.makedirs(os.path.dirname(op["path"]), exist_ok=True)
        tmp = op["path"] + ".writing"
        with open(tmp, "wb") as f:
            f.write(base64.b64decode(op["b64"]))
        os.replace(tmp, op["path"])
        with open(op["path"], "rb") as f:
            out.append({"sha256": hashlib.sha256(f.read()).hexdigest()})
    elif kind == "sha256":
        try:
            with open(op["path"], "rb") as f:
                out.append({"sha256": hashlib.sha256(f.read()).hexdigest()})
        except OSError as e:
            out.append({"err": str(e)})
print(json.dumps(out))
'''
BOOT = ("import sys;d=sys.stdin.buffer.read();i=d.index(bytes(8));"
        "exec(compile(d[:i],'mt13-remote','exec'),{'DATA':d[i+8:]})")


def utc(t=None):
    return time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime(t))


def quorum_of(count):
    # The least cement that reaches the share: cement * 100 >= 67 * count, as close.rs compares it.
    num, den = QUORUM
    return -(-count * num // den)


def parse_proposal(b):
    if len(b) < DECIDED_LEN + 32:
        raise ValueError("a proposal shorter than its decided part and beacon: %d bytes" % len(b))
    out, at = {}, 0
    for name, width in FIELDS:
        value = b[at:at + width]
        at += width
        out[name] = int.from_bytes(value, "little") if width in (4, 8) else value.hex()
    out["suite_id"] = int.from_bytes(b[DECIDED_LEN - 2:DECIDED_LEN], "little")
    out["final_beacon"] = b[DECIDED_LEN:DECIDED_LEN + 32].hex()
    out["id"] = hashlib.sha256(PROPOSAL_DOMAIN + b[:DECIDED_LEN]).hexdigest()
    out["size"] = len(b)
    return out


class Refused(Exception):
    pass


class Run:
    def __init__(self, topo, args):
        self.topo, self.args, self.dry = topo, args, args.dry_run
        self.run_id = args.run_id
        self.nodes = {n["name"]: n for n in topo["nodes"]}
        self.admitted = [n["name"] for n in topo["nodes"] if n["admitted"]]
        self.evidence = args.evidence or os.path.join(HERE, "evidence", self.run_id)
        self.root = "%s/%s" % (topo["run_root"], self.run_id)
        self.bin = self.root + "/bin/montana-node"
        self.port = topo["port"]
        self.t = topo["timing"]
        self.k = topo["targets"]
        self.born = {}
        self.known = set()          # sha256 of every proposal the evidence holds
        self.offsets = {}           # how much of each node's log the evidence holds
        self.finals = {}            # window -> the one name every machine took for it, over the run
        self.windows = {}           # window -> its name, roots, cement and the objects of every holder
        self.seq = 0
        self.failed = False
        self.stopped_early = None
        self.checks = []
        self.commands = []

    # -- paths and names of the far side ------------------------------------------------------
    def data(self, n):
        return "%s/%s/data" % (self.root, n)

    def log(self, n):
        return "%s/%s/node.log" % (self.root, n)

    def handoff(self, n):
        return "%s/%s/handoff" % (self.root, n)

    def unit(self, n):
        return "mt13-%s-%s" % (self.run_id.lower(), n)

    def inside(self, n):
        ns = self.nodes[n].get("netns")
        return ["ip", "netns", "exec", ns] if ns else []

    def listen(self, n):
        return "%s:%d" % (self.nodes[n]["address"], self.port)

    # -- the record ---------------------------------------------------------------------------
    def say(self, line):
        print(line, flush=True)

    def write(self, rel, data):
        if self.dry:
            return
        at = os.path.join(self.evidence, rel)
        os.makedirs(os.path.dirname(at), exist_ok=True)
        with open(at, "wb" if isinstance(data, bytes) else "w") as f:
            f.write(data)

    def append(self, rel, data):
        if self.dry:
            return
        at = os.path.join(self.evidence, rel)
        os.makedirs(os.path.dirname(at), exist_ok=True)
        with open(at, "ab") as f:
            f.write(data)

    # -- the far side -------------------------------------------------------------------------
    def remote(self, host, ops):
        ssh = self.topo["hosts"][host]["ssh"] + [shlex.join(["python3", "-I", "-c", BOOT])]
        self.say("  %s" % shlex.join(ssh[:-1] + ["python3 -I -c <executor>"]))
        for op in ops:
            if op["op"] == "run":
                self.say("    [%s] %s%s" % (host, shlex.join(op["argv"]), "   (cwd %s)" % op["cwd"] if op.get("cwd") else ""))
            elif op["op"] == "put":
                self.say("    [%s] put %s (%s)" % (host, op["path"], op.get("what", "")))
            else:
                self.say("    [%s] %s %s" % (host, op["op"], op.get("data") or op.get("path")))
        if self.dry:
            return [None] * len(ops)
        payload = REMOTE.encode() + bytes(8) + json.dumps({"ops": ops}).encode()
        limit = 120 + sum(op.get("timeout", 120) for op in ops)
        began = time.time()
        try:
            r = subprocess.run(ssh, input=payload, capture_output=True, timeout=limit)
        except subprocess.TimeoutExpired:
            raise Refused("%s did not answer within %d s" % (host, limit))
        if r.returncode != 0:
            raise Refused("%s: ssh rc %d: %s" % (host, r.returncode, r.stderr.decode(errors="replace")[-400:]))
        got = json.loads(r.stdout.decode().strip().splitlines()[-1])
        for op, res in zip(ops, got):
            if op["op"] == "run":
                self.commands.append({"utc": utc(began), "host": host, "argv": op["argv"], "cwd": op.get("cwd"),
                                      "rc": res.get("rc"), "timeout": res.get("timeout", False)})
        return got

    def run_on(self, host, argv, timeout=120, cwd=None):
        op = {"op": "run", "argv": argv, "timeout": timeout}
        if cwd:
            op["cwd"] = cwd
        return self.remote(host, [op])[0]

    def by_host(self, names):
        hosts = {}
        for n in names:
            hosts.setdefault(self.nodes[n]["host"], []).append(n)
        return hosts

    # -- expectations -------------------------------------------------------------------------
    def expect(self, step, name, check):
        if self.dry:
            self.say("    EXPECT %s" % name)
            return True
        try:
            ok, detail = check()
        except Exception as e:  # a check that cannot be evaluated has not held
            ok, detail = False, "the check raised %r" % (e,)
        self.checks.append({"utc": utc(), "step": step, "expect": name, "held": bool(ok), "detail": detail})
        self.say("    %s %s -- %s" % ("HELD  " if ok else "FAILED", name, detail))
        if not ok:
            self.failed = True
        return ok

    # -- the machines -------------------------------------------------------------------------
    def node_args(self, n, opening=False, anchor=None):
        args = ["--data", self.data(n), "--listen", self.listen(n)]
        for other in self.admitted:
            if other != n:
                args += ["--acquaintance", self.born[other]["acquaintance"]]
        if self.nodes[n]["admitted"]:
            for one in self.admitted:
                args += ["--admitted", self.born[one]["half"]]
        if opening:
            args.append("--open")
        if anchor:
            args += ["--anchor", anchor[0], "--anchor", anchor[1]]
        return args

    def start(self, names, opening=False, anchors=None):
        for host, here in self.by_host(names).items():
            ops = []
            for n in here:
                unit = self.topo["unit"]
                argv = ["systemd-run", "--unit", self.unit(n), "--collect", "--quiet",
                        "-p", "Nice=%s" % unit["Nice"], "-p", "MemoryMax=%s" % unit["MemoryMax"],
                        "-p", "StandardOutput=append:%s" % self.log(n),
                        "-p", "StandardError=append:%s" % self.log(n), "--"]
                argv += self.inside(n) + [self.bin] + self.node_args(n, opening, (anchors or {}).get(n))
                ops.append({"op": "run", "argv": argv})
            for n, res in zip(here, self.remote(host, ops)):
                if res is not None and res.get("rc") != 0:
                    raise Refused("machine %s did not start: %s" % (n, res.get("err")))

    def stop(self, names, crash=()):
        for host, here in self.by_host(names).items():
            ops = []
            for n in here:
                if n in crash:
                    ops.append({"op": "run", "argv": ["systemctl", "kill", "--signal=SIGKILL", self.unit(n)]})
                ops.append({"op": "run", "argv": ["systemctl", "stop", self.unit(n)], "timeout": 300})
            self.remote(host, ops)

    def marks(self, names):
        got = {}
        for host, here in self.by_host(names).items():
            ops = [{"op": "marks", "data": self.data(n), "unit": self.unit(n)} for n in here]
            for n, res in zip(here, self.remote(host, ops)):
                got[n] = res
        return got

    def status_argv(self, n):
        return self.inside(n) + [self.bin, "--status", "--data", self.data(n)]

    def snapshot(self, label, names=None):
        names = names or list(self.nodes)
        self.seq += 1
        rel = "snapshots/%02d-%s" % (self.seq, label)
        self.say("  SNAPSHOT %s: %s" % (rel, ", ".join(names)))
        if self.dry:
            for host, here in self.by_host(names).items():
                self.remote(host, [{"op": "snapshot", "data": self.data(n)} for n in here])
                for n in here:
                    self.say("    [%s] %s   (inside the snapshot)" % (host, shlex.join(self.status_argv(n))))
            return None
        snap = {}
        for host, here in self.by_host(names).items():
            ops = [{"op": "snapshot", "data": self.data(n), "unit": self.unit(n), "known": sorted(self.known),
                    "log": self.log(n), "offset": self.offsets.get(n, 0), "status": self.status_argv(n)}
                   for n in here]
            for n, res in zip(here, self.remote(host, ops)):
                proposals = {}
                for name, one in res["proposals"].items():
                    if "b64" in one:
                        b = base64.b64decode(one.pop("b64"))
                        if hashlib.sha256(b).hexdigest() != one["sha256"]:
                            raise Refused("proposal %s of %s changed in flight" % (name, n))
                        self.write("objects/%s.proposal" % one["sha256"], b)
                        self.known.add(one["sha256"])
                    with open(os.path.join(self.evidence, "objects", one["sha256"] + ".proposal"), "rb") as f:
                        parsed = parse_proposal(f.read())
                    proposals[int(name)] = {"file": name, "sha256": one["sha256"], "parsed": parsed}
                if "log" in res:
                    chunk = base64.b64decode(res.pop("log")["b64"])
                    self.append("logs/%s.log" % n, chunk)
                    self.offsets[n] = self.offsets.get(n, 0) + len(chunk)
                res["proposals"] = {str(w): {k: v for k, v in p.items()} for w, p in proposals.items()}
                self.write("%s/%s.json" % (rel, n), json.dumps(res, indent=1, sort_keys=True))
                res["proposals"] = proposals
                snap[n] = res
        self.invariants(label, snap)
        return snap

    def logged(self, n):
        at = os.path.join(self.evidence, "logs", n + ".log")
        if not os.path.exists(at):
            return ""
        with open(at, errors="replace") as f:
            return f.read()

    # -- what holds at every snapshot ---------------------------------------------------------
    def invariants(self, label, snap):
        step = "invariants@" + label

        def files_are_their_windows():
            bad = [(n, w) for n, s in snap.items() for w, p in s["proposals"].items() if p["parsed"]["window"] != w]
            return not bad, "every proposals/<w> carries window w" if not bad else "mismatched %r" % bad

        def chains_link():
            bad = []
            for n, s in snap.items():
                for w, p in s["proposals"].items():
                    before = s["proposals"].get(w - 1)
                    if before and p["parsed"]["previous"] != before["parsed"]["id"]:
                        bad.append((n, w))
            return not bad, "proposal(w).previous = id(proposal(w-1)) on every machine" if not bad else "broken at %r" % bad

        def finals_have_one_name():
            # A machine of the opening cohort holds every window from zero; a machine that joined
            # holds them from its anchor. mt-store removes dead temporaries, agreements and points,
            # never a proposal (mt-store/src/lib.rs:230-243, :628-637, :865-880).
            seen, bad = {}, []
            for n, s in snap.items():
                head = s["marks"].get("head")
                if head is None:
                    continue
                lowest = 0 if self.nodes[n]["admitted"] else min(s["proposals"], default=0)
                for w in range(lowest, head + 1):
                    p = s["proposals"].get(w)
                    if p is None:
                        bad.append((n, w, "missing"))
                        continue
                    name = p["parsed"]["id"]
                    if seen.setdefault(w, name) != name or self.finals.setdefault(w, name) != name:
                        bad.append((n, w, name[:16]))
            return not bad, "one name for every final window, here and across the run (%d windows)" % len(seen) if not bad else "%r" % bad

        def cement_reaches_the_quorum():
            bad = []
            need = quorum_of(len(self.admitted))
            for n, s in snap.items():
                for w, p in s["proposals"].items():
                    c = p["parsed"]["cement_count"]
                    if s["marks"].get("head") is not None and w <= s["marks"]["head"] and not (need <= c <= len(self.admitted)):
                        bad.append((n, w, c))
            return not bad, "every final cement counts %d..%d of %d" % (need, len(self.admitted), len(self.admitted)) if not bad else "%r" % bad

        def the_log_names_what_the_store_holds():
            # A final line names the proposal for good; a closed line may name one the machine later
            # replaces by the decided one (four_machines_decide_one_name.rs:15-20), so only the first
            # kind is held against the store.
            bad, said = [], 0
            for n, s in snap.items():
                for m in FINAL_LINE.finditer(self.logged(n)):
                    w, name = int(m.group(1)), m.group(2)
                    p = s["proposals"].get(w)
                    if p is not None:
                        said += 1
                        if p["parsed"]["id"] != name:
                            bad.append((n, w))
            return not bad, "%d final lines of the logs name the proposals the stores hold" % said if not bad else "%r" % bad

        # What each final window is, kept for the evidence: its name, its roots, its cement and the
        # bytes every machine holds of it.
        for n, s in snap.items():
            head = s["marks"].get("head")
            for w, p in s["proposals"].items():
                if head is not None and w <= head:
                    one = self.windows.setdefault(w, {"id": p["parsed"]["id"], "previous": p["parsed"]["previous"],
                                                      "roots": {r: p["parsed"][r] for r in ROOTS},
                                                      "admitted_count": p["parsed"]["admitted_count"],
                                                      "cement_count": p["parsed"]["cement_count"], "held": {}})
                    one["held"][n] = {"object": p["sha256"], "final_beacon": p["parsed"]["final_beacon"], "size": p["parsed"]["size"]}

        self.expect(step, "proposal files carry their windows", files_are_their_windows)
        self.expect(step, "every chain links by identifier", chains_link)
        self.expect(step, "a final window has one name", finals_have_one_name)
        self.expect(step, "a final cement reaches the quorum and no more than the electorate", cement_reaches_the_quorum)
        self.expect(step, "the logs and the stores agree", the_log_names_what_the_store_holds)

    # -- waiting ------------------------------------------------------------------------------
    def wait(self, what, names, done, budget, living=None):
        self.say("  WAIT up to %d s, polling every %d s: %s" % (budget, self.t["poll_s"], what))
        if self.dry:
            self.marks(names)
            return None
        deadline = time.time() + budget
        while True:
            got = self.marks(names)
            dead = [n for n in (living or []) if got[n].get("active") != "active"]
            if dead:
                return {"dead": dead, "marks": got}
            if done(got):
                return {"marks": got}
            if time.time() > deadline:
                return {"timeout": True, "marks": got}
            time.sleep(self.t["poll_s"])

    def heads(self, got, names):
        return {n: got[n].get("head") for n in names}

    def all_heads_at_least(self, names, target):
        return lambda got: all((got[n].get("head") is not None and got[n]["head"] >= target) for n in names)

    def waited(self, step, what, outcome):
        def check():
            if outcome is None:
                return False, "no outcome"
            if outcome.get("dead"):
                return False, "machines stopped living: %s; marks %r" % (outcome["dead"], outcome["marks"])
            if outcome.get("timeout"):
                return False, "the budget ran out; marks %r" % outcome["marks"]
            return True, "marks %r" % outcome["marks"]
        return self.expect(step, what, check)

    def hold(self, step, what, names, still, budget):
        # A stretch in which nothing may move: polled to its end, failing at the first change.
        self.say("  HOLD %d s, polling every %d s: %s" % (budget, self.t["poll_s"], what))
        if self.dry:
            self.marks(names)
            self.say("    EXPECT %s" % what)
            return
        end, moved = time.time() + budget, None
        while time.time() < end and moved is None:
            got = self.marks(names)
            changed = [n for n in names if (got[n].get("head"), got[n].get("closed")) != still[n]]
            if changed:
                moved = (changed, got)
                break
            time.sleep(self.t["poll_s"])
        self.expect(step, what, lambda: (moved is None, "nothing moved for %d s" % budget if moved is None else "moved: %r" % (moved,)))

    def still(self, snap, names):
        if snap is None:
            return {n: None for n in names}
        return {n: (snap[n]["marks"].get("head"), snap[n]["marks"].get("closed")) for n in names}

    # -- partitions ---------------------------------------------------------------------------
    def cut(self, groups):
        # Each machine drops the run's port to and from every machine outside its group, in a table
        # of its own (inet mt13) inside its own namespace.
        where = {n: i for i, g in enumerate(groups) for n in g}
        for host, here in self.by_host(list(where)).items():
            ops = []
            for n in here:
                others = [self.nodes[o]["address"] for o in where if where[o] != where[n]]
                if not others:
                    continue
                s = "{ %s }" % ", ".join(others)
                p = self.port
                nft = self.inside(n) + ["nft"]
                for rule in ("add table inet mt13",
                             "add chain inet mt13 out { type filter hook output priority 0 ; policy accept ; }",
                             "add chain inet mt13 in { type filter hook input priority 0 ; policy accept ; }",
                             "add rule inet mt13 out ip daddr %s tcp dport %d drop" % (s, p),
                             "add rule inet mt13 out ip daddr %s tcp sport %d drop" % (s, p),
                             "add rule inet mt13 in ip saddr %s tcp dport %d drop" % (s, p),
                             "add rule inet mt13 in ip saddr %s tcp sport %d drop" % (s, p)):
                    ops.append({"op": "run", "argv": nft + [rule]})
            for res in self.remote(host, ops):
                if res is not None and res.get("rc") != 0:
                    raise Refused("a partition rule was refused: %s" % res.get("err"))

    def heal(self, names):
        for host, here in self.by_host(names).items():
            self.remote(host, [{"op": "run", "argv": self.inside(n) + ["nft", "delete table inet mt13"]} for n in here])

    def anchor_of(self, n, source, snap, earlier):
        # Two consecutive final proposals of `source`, handed to `n` as files: what an operator does.
        paths = []
        for w in ((earlier, "%s + 1" % earlier) if self.dry else (earlier, earlier + 1)):
            path = "%s/anchor-%s" % (self.handoff(n), w if self.dry else "%020d" % w)
            if self.dry:
                self.remote(self.nodes[n]["host"], [{"op": "put", "path": path, "what": "proposal of window %s from %s" % (w, source)}])
            else:
                sha = snap[source]["proposals"][w]["sha256"]
                with open(os.path.join(self.evidence, "objects", sha + ".proposal"), "rb") as f:
                    b = f.read()
                got = self.remote(self.nodes[n]["host"], [{"op": "put", "path": path, "b64": base64.b64encode(b).decode(), "what": "window %d from %s" % (w, source)}])[0]
                if got["sha256"] != sha:
                    raise Refused("the anchor handed to %s is not the proposal it was read as" % n)
            paths.append(path)
        return paths

    # -- the steps ----------------------------------------------------------------------------
    def s0_prepare(self):
        step = "S0 prepare"
        self.say("\n== %s" % step)
        for name, host in self.topo["hosts"].items():
            if any(r in " ".join(host["ssh"]) for r in REFUSED_HOSTS):
                raise Refused("host %s is refused: Lauterbourg-3 carries Kani by the author's word" % name)
        for n, node in self.nodes.items():
            if self.data(n).startswith(REFUSED_DATA) or self.topo["run_root"].startswith(REFUSED_DATA):
                raise Refused("the store of %s would stand beside the live cohort net4" % n)
        build = [h for h, v in self.topo["hosts"].items() if v.get("build")][0]
        src, commit = self.topo["source"], self.args.commit
        for host in self.topo["hosts"]:
            res = self.run_on(host, ["test", "!", "-e", self.root])
            if res is not None and res["rc"] != 0:
                raise Refused("%s already holds %s: a run starts on empty stores" % (host, self.root))
        res = self.run_on(build, ["test", "-d", src + "/.git"])
        if self.dry or res["rc"] != 0:
            self.run_on(build, ["git", "clone", "--quiet", "--no-checkout", self.topo["repo"], src], timeout=1800)
        self.run_on(build, ["git", "-C", src, "fetch", "--quiet", "origin"], timeout=1800)
        self.run_on(build, ["git", "-C", src, "checkout", "--quiet", "--detach", commit])
        head = self.run_on(build, ["git", "-C", src, "rev-parse", "HEAD"])
        self.expect(step, "the source stands at the commit asked", lambda: (head["out"].strip() == commit, head["out"].strip()))
        for need in self.topo.get("required_commits", []):
            r = self.run_on(build, ["git", "-C", src, "merge-base", "--is-ancestor", need, "HEAD"])
            self.expect(step, "the commit carries %s" % need, lambda r=r: (r["rc"] == 0, "rc %s" % r["rc"]))
        core = src + "/core/Montana-Core"
        r = self.run_on(build, [self.topo["cargo"], "build", "--release", "--locked", "-p", "montana-node"], timeout=self.t["build_s"], cwd=core)
        self.expect(step, "the release binary builds", lambda: (r["rc"] == 0, "rc %s %s" % (r["rc"], r["err"][-300:])))
        if self.failed:
            raise Refused("the binary did not build")
        self.run_on(build, ["install", "-D", "-m", "0755", core + "/target/release/montana-node", self.bin])
        got = self.remote(build, [{"op": "sha256", "path": self.bin}])[0]
        if got:
            self.write("binary.sha256", "%s  montana-node\n" % got["sha256"])
            self.binary = got["sha256"]
        usage = self.run_on(build, [self.bin, "--help"])
        for flag in ("--open", "--admitted", "--acquaintance", "--anchor", "--status"):
            self.expect(step, "the binary knows %s" % flag, lambda flag=flag: (flag in usage["out"], "montana-node --help"))
        if self.failed:
            raise Refused("a prerequisite of the run is not in this binary (RUN.md, Prerequisites)")
        # The namespaces: a hub holding a bridge, and one namespace per machine wired to it. Every
        # link is created with both ends already inside namespaces, so the host's own namespace
        # never holds one.
        hub = self.topo.get("hub")
        if hub:
            ops = [["ip", "netns", "add", hub["netns"]],
                   ["ip", "-n", hub["netns"], "link", "set", "lo", "up"],
                   ["ip", "-n", hub["netns"], "link", "add", hub["bridge"], "type", "bridge"],
                   ["ip", "-n", hub["netns"], "link", "set", hub["bridge"], "up"]]
            for n, node in self.nodes.items():
                ns = node["netns"]
                if node["host"] != hub["host"] or not ns:
                    raise Refused("topology A puts every machine in a namespace on the hub's host; %s is not" % n)
                ops += [["ip", "netns", "add", ns],
                        ["ip", "link", "add", "mt13-%s0" % n, "netns", ns, "type", "veth", "peer", "name", "mt13-%s1" % n, "netns", hub["netns"]],
                        ["ip", "-n", ns, "link", "set", "lo", "up"],
                        ["ip", "-n", ns, "addr", "add", node["address"] + "/24", "dev", "mt13-%s0" % n],
                        ["ip", "-n", ns, "link", "set", "mt13-%s0" % n, "up"],
                        ["ip", "-n", hub["netns"], "link", "set", "mt13-%s1" % n, "master", hub["bridge"]],
                        ["ip", "-n", hub["netns"], "link", "set", "mt13-%s1" % n, "up"]]
            for res in self.remote(hub["host"], [{"op": "run", "argv": a} for a in ops]):
                if res is not None and res["rc"] != 0:
                    raise Refused("the namespaces were not built: %s" % res["err"])
        for host, here in self.by_host(list(self.nodes)).items():
            for res in self.remote(host, [{"op": "run", "argv": ["mkdir", "-p", self.data(n), self.handoff(n)]} for n in here]):
                if res is not None and res["rc"] != 0:
                    raise Refused("the run's directories were not made on %s: %s" % (host, res["err"]))
        a, b = self.admitted[0], self.admitted[1]
        ping = self.run_on(self.nodes[a]["host"], self.inside(a) + ["ping", "-c", "2", "-W", "2", self.nodes[b]["address"]])
        self.expect(step, "the machines reach one another", lambda: (ping["rc"] == 0, "ping %s -> %s" % (a, b)))
        if hub:
            out = self.run_on(self.nodes[a]["host"], self.inside(a) + ["ip", "route"])
            self.expect(step, "a machine's namespace has no way out", lambda: ("default" not in out["out"], out["out"].strip()))
        self.expect(step, "no single machine reaches the quorum alone",
                    lambda: (quorum_of(len(self.admitted)) >= 2, "quorum %d of %d" % (quorum_of(len(self.admitted)), len(self.admitted))))

    def s1_birth(self):
        step = "S1 birth"
        self.say("\n== %s" % step)
        for n in self.nodes:
            argv = ["timeout", "--signal=TERM", str(self.t["birth_s"])] + self.inside(n) + [self.bin, "--data", self.data(n), "--listen", self.listen(n)]
            res = self.run_on(self.nodes[n]["host"], argv, timeout=self.t["birth_s"] + 30)
            if self.dry:
                self.born[n] = {"half": "<half of %s>" % n, "acquaintance": "<acquaintance of %s>" % n}
                self.say("    EXPECT %s is born, prints its acquaintance and its half, and is stopped by timeout (rc 124)" % n)
                continue
            text = res["out"]
            half = re.search(r"hand this over too, to stand in one window: ([0-9a-f]{64})", text)
            line = re.search(r"hand this to another operator: (\S+)", text)
            digits = re.search(r"check these digits with them by voice: (.+)", text)
            self.write("birth/%s.out" % n, text + "\n--- stderr\n" + res["err"] + "\n--- rc %s\n" % res["rc"])
            ok = self.expect(step, "%s is born and names itself" % n,
                             lambda: (res["rc"] == 124 and "this machine was born" in text and half and line,
                                      "rc %s, half %s" % (res["rc"], half.group(1)[:16] if half else None)))
            if ok:
                self.born[n] = {"half": half.group(1), "acquaintance": line.group(1),
                                "fingerprint": digits.group(1).strip() if digits else None}
                self.expect(step, "%s answers at its own address" % n,
                            lambda: (line.group(1).startswith(self.listen(n) + "@"), line.group(1)[:40]))
        self.write("birth/born.json", json.dumps(self.born, indent=1, sort_keys=True))

    def s2_open(self):
        step = "S2 windows close"
        self.say("\n== %s" % step)
        self.start(self.admitted, opening=True)
        target = self.k["open_final"] - 1
        out = self.wait("every admitted machine holds window %d final" % target, self.admitted,
                        self.all_heads_at_least(self.admitted, target), self.t["window_budget_s"] * (target + 2), living=self.admitted)
        self.waited(step, "windows 0..%d are final on all four" % target, out)
        self.snapshot("open", self.admitted)

    def s3_quorum_lost_by_stop(self):
        step = "S3 quorum lost by a stop, recovered by a restart"
        self.say("\n== %s" % step)
        a, b, c, d = self.admitted[:4]
        self.stop([c, d])
        before = self.snapshot("two-stopped", self.admitted)
        self.expect(step, "%s and %s are stopped" % (c, d),
                    lambda: (all(before[x]["active"] != "active" for x in (c, d)), {x: before[x]["active"] for x in (c, d)}))
        self.hold(step, "two of four close nothing and move no head", [a, b], self.still(before, [a, b]), self.t["hold_s"])
        during = self.snapshot("held-without-quorum", self.admitted)
        def no_new_close(x):
            # Which of the readings of #21 a quorum lost by a stop shows is recorded, not presumed:
            # what must hold is that diagnostics are present and no close is read past the last one.
            st = during[x]["status"]
            said = re.search(r"closed window (\d+)", st["out"])
            last = before[x]["marks"]["closed"]
            ok = st["rc"] != 4 and (said is None or (last is not None and int(said.group(1)) <= last))
            return ok, "rc %s: %s" % (st["rc"], st["out"][:160])

        for x in (a, b):
            self.expect(step, "%s keeps the proposals it held" % x,
                        lambda x=x: (sorted(during[x]["proposals"]) == sorted(before[x]["proposals"]), sorted(during[x]["proposals"])[-3:]))
            self.expect(step, "%s's status is a reading, not missing diagnostics, and names no new close" % x,
                        lambda x=x: no_new_close(x))
        self.start([c, d])
        top = None if self.dry else max(during[x]["marks"]["head"] for x in (a, b))
        target = None if self.dry else top + self.k["after_recovery"]
        out = self.wait("every machine holds window <head before + %d> final" % self.k["after_recovery"], self.admitted,
                        None if self.dry else self.all_heads_at_least(self.admitted, target),
                        self.t["window_budget_s"] * (self.k["after_recovery"] + 1), living=self.admitted)
        self.waited(step, "the quorum is back and %d more windows are final on all four" % self.k["after_recovery"], out)
        after = self.snapshot("recovered", self.admitted)
        self.unchanged_below(step, before, after, self.admitted)

    def unchanged_below(self, step, before, after, names):
        def check():
            bad = []
            for n in names:
                head = before[n]["marks"].get("head")
                for w, p in before[n]["proposals"].items():
                    if head is not None and w <= head and after[n]["proposals"].get(w, {}).get("sha256") != p["sha256"]:
                        bad.append((n, w))
            return not bad, "the proposals of every window final before stand byte for byte" if not bad else "%r" % bad
        if self.dry:
            self.say("    EXPECT the proposals of every window final before the step stand byte for byte")
            return
        self.expect(step, "final proposals never change", check)

    def s4_minority(self):
        step = "S4 a partition 3:1, the majority goes on, the minority waits and rejoins by verifying"
        self.say("\n== %s" % step)
        a, b, c, d = self.admitted[:4]
        before = self.snapshot("before-cut", self.admitted)
        self.cut([[a, b, c], [d]])
        top = None if self.dry else before[a]["marks"]["head"]
        out = self.wait("%s, %s, %s hold %d more windows final" % (a, b, c, self.k["majority"]), self.admitted,
                        None if self.dry else self.all_heads_at_least([a, b, c], top + self.k["majority"]),
                        self.t["window_budget_s"] * (self.k["majority"] + 1), living=self.admitted)
        self.waited(step, "the majority of three closes without the fourth", out)
        parted = self.snapshot("parted", self.admitted)
        self.expect(step, "the minority moved nothing while parted",
                    lambda: (self.still(parted, [d]) == self.still(before, [d]) and sorted(parted[d]["proposals"]) == sorted(before[d]["proposals"]),
                             "%s: %r" % (d, self.still(parted, [d]))))
        # The parts meet. The third of the majority stops, so no window closes without the fourth,
        # and the fourth comes back by walking from its own anchor.
        self.stop([c])
        self.heal(self.admitted)
        self.stop([d])
        own = None if self.dry else parted[d]["marks"]["head"]
        anchor = self.anchor_of(d, d, parted, "<head of d - 1>" if self.dry else own - 1)
        self.start([d], anchors={d: anchor})
        top = None if self.dry else max(parted[x]["marks"]["head"] for x in (a, b))
        out = self.wait("%s walks to the head and a window closes on %s, %s, %s" % (d, a, b, d), [a, b, d],
                        None if self.dry else self.all_heads_at_least([a, b, d], top + 1), self.t["window_budget_s"] * 3, living=[a, b, d])
        self.waited(step, "the fourth is of the chain again", out)
        met = self.snapshot("met", self.admitted)
        if not self.dry:
            first = top + 1
            self.expect(step, "the first window after the meeting counts the fourth (cement 3 with %s stopped)" % c,
                        lambda: (all(met[x]["proposals"].get(first, {}).get("parsed", {}).get("cement_count") == 3 for x in (a, b, d)),
                                 {x: met[x]["proposals"].get(first, {}).get("parsed", {}).get("cement_count") for x in (a, b, d)}))
            self.expect(step, "the walk is in the fourth's log", lambda: (bool(WALKED_LINE.search(self.logged(d))), (WALKED_LINE.findall(self.logged(d)) or ["none"])[-1]))
        else:
            self.say("    EXPECT the first window after the meeting has cement_count 3 on a, b and d (c stopped)")
            self.say("    EXPECT d's log says 'walked from window W to the head at window H'")
        # The third comes back the same way: it was away for at least one window.
        self.stop([c])
        own = None if self.dry else met[c]["marks"]["head"]
        anchor = self.anchor_of(c, c, met, "<head of c - 1>" if self.dry else own - 1)
        self.start([c], anchors={c: anchor})
        top = None if self.dry else max(met[x]["marks"]["head"] for x in (a, b, d))
        out = self.wait("all four hold one more window final", self.admitted,
                        None if self.dry else self.all_heads_at_least(self.admitted, top + 1), self.t["window_budget_s"] * 3, living=self.admitted)
        self.waited(step, "all four live on together", out)
        after = self.snapshot("four-again", self.admitted)
        self.unchanged_below(step, before, after, self.admitted)

    def s5_even(self):
        step = "S5 a partition 2:2, neither half closes; the parts meet and the same window closes"
        self.say("\n== %s" % step)
        a, b, c, d = self.admitted[:4]
        before = self.snapshot("before-even-cut", self.admitted)
        self.cut([[a, b], [c, d]])
        self.hold(step, "neither half closes a window or moves a head", self.admitted, self.still(before, self.admitted), self.t["partition_hold_s"])
        held = self.snapshot("even-held", self.admitted)
        self.heal(self.admitted)
        top = None if self.dry else max(held[x]["marks"]["head"] for x in self.admitted)
        out = self.wait("all four hold %d more window(s) final, nothing restarted" % self.k["after_heal"], self.admitted,
                        None if self.dry else self.all_heads_at_least(self.admitted, top + self.k["after_heal"]),
                        self.t["window_budget_s"] * (self.k["after_heal"] + 1), living=self.admitted)
        self.waited(step, "the quorum is recovered when the parts meet", out)
        after = self.snapshot("even-met", self.admitted)
        self.unchanged_below(step, before, after, self.admitted)

    def s6_restart_all(self):
        step = "S6 the whole network stops and starts again on its stores"
        self.say("\n== %s" % step)
        a, b, c, d = self.admitted[:4]
        self.stop(self.admitted, crash=[d])
        before = self.snapshot("all-stopped", self.admitted)
        self.expect(step, "all four are stopped (%s by SIGKILL)" % d,
                    lambda: (all(before[x]["active"] != "active" for x in self.admitted), {x: before[x]["active"] for x in self.admitted}))
        self.start(self.admitted)
        top = None if self.dry else max(before[x]["marks"]["head"] for x in self.admitted)
        out = self.wait("all four hold %d more window(s) final after the restart" % self.k["after_restart"], self.admitted,
                        None if self.dry else self.all_heads_at_least(self.admitted, top + self.k["after_restart"]),
                        self.t["window_budget_s"] * (self.k["after_restart"] + 1), living=self.admitted)
        self.waited(step, "the network lives on from where it stopped", out)
        after = self.snapshot("all-restarted", self.admitted)
        self.unchanged_below(step, before, after, self.admitted)

    def s7_join(self):
        step = "S7 a new machine joins from an anchor; a forged anchor is refused"
        self.say("\n== %s" % step)
        joiners = [n for n in self.nodes if not self.nodes[n]["admitted"]]
        if not joiners:
            return
        e, a = joiners[0], self.admitted[0]
        if not 1 <= self.k["join_back"] < RETAINED:
            # The certificates of a window stand at its points for `retained_windows` after it closes;
            # an anchor older than that has nothing to walk.
            raise Refused("join_back must lie within the %d retained windows" % RETAINED)
        now = self.snapshot("before-join", self.admitted)
        head = None if self.dry else now[a]["marks"]["head"]
        earlier = "<head of a - %d>" % self.k["join_back"] if self.dry else max(0, head - self.k["join_back"])
        honest = self.anchor_of(e, a, now, earlier)
        # The forged anchor: the later proposal with one byte of its note root turned.
        forged = ["%s/forged-%s" % (self.handoff(e), os.path.basename(p)) for p in honest]
        if self.dry:
            self.remote(self.nodes[e]["host"], [{"op": "put", "path": forged[0], "what": "the earlier proposal as it is"},
                                                {"op": "put", "path": forged[1], "what": "the later proposal, byte 44 (note_root[0]) xor 1"}])
        else:
            blobs = []
            for w in (earlier, earlier + 1):
                with open(os.path.join(self.evidence, "objects", now[a]["proposals"][w]["sha256"] + ".proposal"), "rb") as f:
                    blobs.append(bytearray(f.read()))
            blobs[1][44] ^= 1
            self.write("join/forged-later.proposal", bytes(blobs[1]))
            self.remote(self.nodes[e]["host"], [{"op": "put", "path": forged[i], "b64": base64.b64encode(bytes(blobs[i])).decode()} for i in (0, 1)])
        argv = ["timeout", "--signal=TERM", str(self.t["refusal_s"])] + self.inside(e) + [self.bin] + self.node_args(e, anchor=forged)
        res = self.run_on(self.nodes[e]["host"], argv, timeout=self.t["refusal_s"] + 60)
        if self.dry:
            self.say("    EXPECT the forged anchor is refused: rc neither 0 nor 124, and %s keeps no proposal and no window record" % e)
        else:
            self.write("join/forged.out", res["out"] + "\n--- stderr\n" + res["err"] + "\n--- rc %s\n" % res["rc"])
            after_forged = self.snapshot("forged-refused", [e])
            self.expect(step, "the forged anchor is refused", lambda: (res["rc"] not in (0, 124, None), "rc %s: %s" % (res["rc"], res["err"].strip()[-200:])))
            self.expect(step, "the refusal wrote no chain", lambda: (after_forged[e]["marks"] == {"head": None, "closed": None} and not after_forged[e]["proposals"],
                                                                      "%r, %d proposals" % (after_forged[e]["marks"], len(after_forged[e]["proposals"]))))
        self.start([e], anchors={e: honest})
        out = self.wait("%s walks to the head of the network" % e, [a, e],
                        None if self.dry else self.all_heads_at_least([e], head), self.t["window_budget_s"], living=[e])
        self.waited(step, "the new machine reaches the head", out)
        joined = self.snapshot("joined", self.admitted + [e])
        if self.dry:
            self.say("    EXPECT e's proposals from the anchor to its head are byte-identical names of a's")
            self.say("    EXPECT e's log says 'walked from window W to the head at window H' with H = e's head")
            return
        def same_chain():
            he = joined[e]["marks"]["head"]
            bad = [w for w in range(earlier, he + 1) if joined[e]["proposals"].get(w, {}).get("parsed", {}).get("id") != joined[a]["proposals"].get(w, {}).get("parsed", {}).get("id")]
            return not bad, "windows %d..%d one name on %s and %s" % (earlier, he, e, a) if not bad else "differ at %r" % bad
        self.expect(step, "the new machine holds the network's chain", same_chain)
        walked = WALKED_LINE.findall(self.logged(e))
        self.expect(step, "the walk is in the new machine's log and ends at its head",
                    lambda: (bool(walked) and int(walked[-1][1]) == joined[e]["marks"]["head"], walked[-1:] or "none"))

    def finish(self, code):
        self.say("\n== finish")
        try:
            self.snapshot("last")
        except Refused as e:
            self.say("  the last snapshot was not taken: %s" % e)
            code = max(code, 2)
        for host, here in self.by_host(list(self.nodes)).items():
            try:
                self.remote(host, [{"op": "run", "argv": ["systemctl", "stop", self.unit(n)], "timeout": 300} for n in here])
            except Refused as e:
                self.say("  units on %s were not stopped: %s" % (host, e))
        if self.dry:
            self.say("\nDRY RUN: nothing was run; %d snapshots and every command of them printed above." % self.seq)
            return 0
        if self.failed:
            code = max(code, 1)
        self.write("windows.json", json.dumps({str(w): v for w, v in sorted(self.windows.items())}, indent=1, sort_keys=True))
        manifest = {"run_id": self.run_id, "commit": self.args.commit, "binary_sha256": getattr(self, "binary", None),
                    "topology": self.topo, "finished": utc(), "exit": code, "stopped_early": self.stopped_early,
                    "finals": {str(w): n for w, n in sorted(self.finals.items())},
                    "note": "Our own reproduction on our own servers (Protocol-13 item 13); not an independent external audit."}
        self.write("manifest.json", json.dumps(manifest, indent=1, sort_keys=True))
        self.write("commands.json", json.dumps(self.commands, indent=1))
        self.write("checks.json", json.dumps(self.checks, indent=1))
        sums = []
        for top, _, files in os.walk(self.evidence):
            for name in sorted(files):
                at = os.path.join(top, name)
                rel = os.path.relpath(at, self.evidence)
                if rel == "SHA256SUMS":
                    continue
                with open(at, "rb") as f:
                    sums.append("%s  %s" % (hashlib.sha256(f.read()).hexdigest(), rel))
        self.write("SHA256SUMS", "\n".join(sorted(sums, key=lambda s: s[66:])) + "\n")
        held = sum(1 for c in self.checks if c["held"])
        self.say("\n%d of %d expectations held; evidence in %s; exit %d" % (held, len(self.checks), self.evidence, code))
        return code

    def go(self):
        steps = [self.s0_prepare, self.s1_birth, self.s2_open, self.s3_quorum_lost_by_stop,
                 self.s4_minority, self.s5_even, self.s6_restart_all, self.s7_join]
        if self.args.only:
            steps = [s for s in steps if s.__name__.split("_")[0] in self.args.only.split(",") or s.__name__ in ("s0_prepare", "s1_birth")]
        code = 0
        try:
            for s in steps:
                s()
                if self.failed and not self.args.keep_going:
                    self.stopped_early = s.__name__
                    self.say("\nan expectation failed in %s: the steps after it are not run (--keep-going runs them)" % s.__name__)
                    break
        except Refused as e:
            self.say("\nREFUSED: %s" % e)
            self.stopped_early = "refused: %s" % e
            code = 2
        return self.finish(code)

    def teardown(self):
        self.say("== teardown of %s: units stopped, namespaces removed; stores and logs stay" % self.run_id)
        for host, here in self.by_host(list(self.nodes)).items():
            ops = [{"op": "run", "argv": ["systemctl", "stop", self.unit(n)], "timeout": 300} for n in here]
            ops += [{"op": "run", "argv": ["ip", "netns", "del", self.nodes[n]["netns"]]} for n in here if self.nodes[n].get("netns")]
            self.remote(host, ops)
        self.run_on(self.topo["hub"]["host"], ["ip", "netns", "del", self.topo["hub"]["netns"]])
        return 0


def main():
    p = argparse.ArgumentParser(description="Protocol-13 item 13: the full network run (our own reproduction, not an external audit)")
    p.add_argument("--topology", default=os.path.join(HERE, "topology.json"))
    p.add_argument("--commit", help="the 40-hex commit of main the run builds; required unless --dry-run")
    p.add_argument("--run-id", default=time.strftime("%Y%m%dT%H%MZ", time.gmtime()))
    p.add_argument("--evidence", help="where the evidence is written (default evidence/<run-id> beside this file)")
    p.add_argument("--dry-run", action="store_true", help="print every command, run none")
    p.add_argument("--keep-going", action="store_true", help="run the later steps after an expectation failed")
    p.add_argument("--only", help="comma-separated steps after S0-S1, e.g. s2,s3")
    p.add_argument("--teardown", action="store_true", help="stop the run's units and remove its namespaces")
    p.add_argument("--parse", nargs="+", metavar="FILE", help="print the window, name, link and roots of kept proposals, and nothing else")
    args = p.parse_args()
    if args.parse:
        for at in args.parse:
            with open(at, "rb") as f:
                print(json.dumps({"file": at, **parse_proposal(f.read())}, sort_keys=True))
        sys.exit(0)
    with open(args.topology) as f:
        topo = json.load(f)
    if not re.fullmatch(r"[0-9A-Za-z]+", args.run_id):
        print("--run-id is letters and digits", file=sys.stderr)
        sys.exit(2)
    if args.dry_run:
        args.commit = args.commit or "<commit of main carrying #16-#22>"
    elif not args.teardown and not re.fullmatch(r"[0-9a-f]{40}", args.commit or ""):
        print("--commit names the full commit the run builds", file=sys.stderr)
        sys.exit(2)
    run = Run(topo, args)
    print("Protocol-13 item 13 -- the full network run %s, %s%s" % (args.run_id, utc(), " (DRY RUN)" if args.dry_run else ""))
    print("Our own reproduction on our own servers; not an independent external audit.")
    if args.dry_run:
        print("Every ssh below runs: python3 -I -c %r" % BOOT)
        print("with the executor REMOTE of run.py (sha256 %s) and the listed operations on its standard input."
              % hashlib.sha256(REMOTE.encode()).hexdigest())
    if args.teardown:
        sys.exit(run.teardown())
    sys.exit(run.go())


if __name__ == "__main__":
    main()
