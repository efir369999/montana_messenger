#!/usr/bin/env python3
"""The coin chains of version 3 (Audit/App/COIN-TX-V3.md), recomputed outside both apps from the document alone.

    python3 -I tools/coin_vectors.py

Section 9's vectors that need no signature: V1 the receiver's commitment, V2 the blind, V3 the time a key may mint A(x),
V4 the root of a checkpoint, and V6 the fold of a chain that holds a version 2 record. V5 (a SEND and its RECV signed by a
deterministic ML-DSA-65) needs the core and is checked on the phone (CoinChain.agreesWithCanon). Every value printed here must
equal the document's; a FAIL means a formula was misread. The wrong readings the document names are printed too, and must differ.
"""
import hashlib
import hmac
import struct
import sys

V2_CUT = 1_792_443_600      # 20.10.2026 00:00 MSK
COIN_EPOCH = 1_788_210_000  # 01.09.2026 00:00 MSK
SEND, RECV, MINT, REFUND, GENESIS = 1, 2, 3, 4, 5
ZERO = "0" * 64


def sha(*parts):
    return hashlib.sha256(b"".join(parts)).digest()


def commitment(frm, blind):
    return sha(b"mt-coin-to", frm, blind)


def blind(secret, nonce):
    return hmac.new(secret, b"mt-coin-blind" + nonce, hashlib.sha256).digest()


def time_a(x):
    total, lo, k = 0, 1, 0
    while 0 < x and lo <= x:
        hi = min(x, 2 * lo - 1)
        total += (hi - lo + 1) * min(13, max(1, k))
        lo, k = 2 * lo, k + 1
    return 2 * total


def time_a_slow(x):   # the definition itself: rate(s) = 2 x min(13, max(1, bit_length(s) - 1))
    return sum(2 * min(13, max(1, s.bit_length() - 1)) for s in range(1, x + 1))


def root(T, chains):
    """chains: from (32 bytes) -> [(record id 32 bytes, at)] in chain order."""
    h = hashlib.sha256(b"mt-coin-root-v1")
    for frm in sorted(chains):
        ids = [i for i, at in chains[frm] if at <= T]
        if not ids:
            continue
        h.update(frm + ids[-1] + struct.pack("<Q", len(ids)))
    return h.hexdigest()


class St:
    def __init__(self):
        self.head, self.height, self.birth, self.mint_end = ZERO, 0, 0, 0
        self.proven = self.declared = self.minted = 0
        self.v3 = False


def step(s, version, kind, amount, at, a=0, b=0, ref=None, sends=None, frm=None, to=None, settled=()):
    """One record onto a key's state by section 3; None for a record the node refuses (409)."""
    n = St()
    n.__dict__.update(s.__dict__)
    n.height += 1
    if s.height == 0:
        n.birth = n.mint_end = at
    if version == 2:
        if not s.v3:
            return n
        if s.proven + s.declared < amount:
            return None
        d = max(0, amount - s.proven)
        n.proven, n.declared = s.proven - (amount - d), s.declared - d
        return n
    n.v3 = True
    if kind == GENESIS:
        if s.v3 or (0 < amount and V2_CUT <= at) or time_a(V2_CUT - COIN_EPOCH) < amount:
            return None
        n.declared = amount
    elif kind == MINT:
        if s.height == 0 or a < s.mint_end or b < a + 60 or at < b or time_a(b - s.birth) - s.minted < amount:
            return None
        n.proven, n.mint_end, n.minted = s.proven + amount, b, s.minted + amount
    elif kind == SEND:
        if s.proven + s.declared < amount or a != max(0, amount - s.proven):
            return None
        n.proven, n.declared = s.proven - (amount - a), s.declared - a
    elif kind in (RECV, REFUND):
        S = sends[ref]
        if S["amount"] != amount or ref in settled:
            return None
        if kind == RECV and (S["dec"] != a or commitment(frm, to) != S["to"]):
            return None
        if kind == REFUND and (S["from"] != frm or at < S["at"] + 86_400):
            return None
        n.proven, n.declared = s.proven + amount - S["dec"], s.declared + S["dec"]
    else:
        return None
    return n


def main():
    ok = True

    def check(name, got, want, refuse=()):
        nonlocal ok
        good = got == want and all(got != r for r in refuse)
        ok &= good
        print(("ok   " if good else "FAIL ") + name + " " + str(got))

    frm = bytes(range(0x00, 0x20))
    bl = bytes(range(0x20, 0x40))
    check("V1 commitment", commitment(frm, bl).hex(), "b08fb9c67b693f0cfe394de25474d2b79ae990a87a2f6a24bb7727560a8d88a4")
    check("V1 refuses the blind first", sha(b"mt-coin-to", bl, frm).hex(), "8d9016dfed6ea8b2c6c03daaf943afe73dfc25ed46a4bc9049bf5afe15de9c3f")
    check("V2 blind", blind(bytes(range(0x40, 0x60)), bytes(range(0x60, 0x70))).hex(),
          "530efcc186fe26cb48fb4023c7a7e884c94516d14e62feaa06e81c76f89d7be4")
    check("V2 refuses key and message swapped",
          hmac.new(b"mt-coin-blind" + bytes(range(0x60, 0x70)), bytes(range(0x40, 0x60)), hashlib.sha256).hexdigest(),
          "c9791acc18552bdd84114470faa6aa038af2f0ab245b4bfdb0ea9cd2e93ceb16")
    want = {1: 2, 2: 4, 3: 6, 4: 10, 7: 22, 8: 28, 15: 70, 16: 78, 8191: 180230, 8192: 180256, 8193: 180282, 86400: 2213664}
    check("V3 A(x)", {x: time_a(x) for x in want}, want)
    check("V3 closed form = the definition", all(time_a(x) == time_a_slow(x) for x in range(0, 20000)), True)
    check("V3 the genesis cap", time_a(V2_CUT - COIN_EPOCH), time_a(V2_CUT - COIN_EPOCH))

    keys = {c: sha(("root key " + c).encode()) for c in "abc"}
    counts = {"a": 3, "c": 2, "b": 1}
    chains = {keys[c]: [(sha(("root head %s %d" % (c, i)).encode()), 100 + i) for i in range(counts[c])] for c in "acb"}
    check("V4 root", root(1000, chains), "4db30532f47a38696a81aa103cabea16ecf6034934cf26decbb9e78ad848b5e1")
    h = hashlib.sha256(b"mt-coin-root-v1")
    for c in "acb":
        ids = chains[keys[c]]
        h.update(keys[c] + ids[-1][0] + struct.pack(">Q", len(ids)))
    check("V4 refuses the laid order, count big-endian", h.hexdigest(), "b5cb0949009d6d9f9c34d20f5e719de913930ba61afd4e96835a1575efea07a6")

    # V6: GENESIS 1000 declared, MINT 500, SEND 1200 (dec 700), a v2 record of 50 -> proven 0, declared 250; a v2 of 251 -> 409
    t = 1_792_000_000
    s = step(St(), 3, GENESIS, 1000, t)
    s = step(s, 3, MINT, 500, t + 600, a=t, b=t + 300)
    s = step(s, 3, SEND, 1200, t + 601, a=700)
    s2 = step(s, 2, 0, 50, t + 602)
    check("V6 a v2 record on an opened chain", (s2.proven, s2.declared), (0, 250))
    check("V6 a v2 of 251 next is an overspend", step(s2, 2, 0, 251, t + 603), None)
    # the Explorer's run: GENESIS 0, MINT 1000, SEND 100, a v2 record of 50 -> balance 850
    e = step(St(), 3, GENESIS, 0, t)
    e = step(e, 3, MINT, 1000, t + 1200, a=t, b=t + 1200)
    e = step(e, 3, SEND, 100, t + 1201, a=0)
    e = step(e, 2, 0, 50, t + 1202)
    check("V6 the Explorer's run", e.proven + e.declared, 850)
    # a v2 record before the chain opened moves nothing
    p = step(St(), 2, 0, 50, t)
    check("V6 a v2 record before the first v3 moves nothing", (p.proven, p.declared, p.v3), (0, 0, False))
    print("coin_vectors: " + ("all hold" if ok else "MISMATCH"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
