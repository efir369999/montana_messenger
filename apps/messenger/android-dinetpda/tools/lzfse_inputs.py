#!/usr/bin/env python3
"""THE INPUTS OF THE LZFSE CHECK (tools/lzfse_check.sh): the vault's own JSON of moves, random, repeated and worded bytes of every
size around the encoder's edges (8 bytes, the LZVN threshold of 4 096, many blocks), and from the reference's streams of them the
damaged ones and the same streams with their bvx2 headers laid as bvx1. Python's standard library alone; fixed seeds."""
import json
import random
import struct
import sys
from pathlib import Path


def moves(n, rnd):
    kinds = ["earn", "receive", "spend", "send", "burn"]
    out = []
    for i in range(n):
        k = rnd.choice(kinds)
        e = {"k": k, "c": rnd.randint(1, 5_000_000), "ref": rnd.choice(["tap:w", "tap:pull-w", "mid:t", "tx:", "txback:", "cmt:"])
             + str(1760000000000 + rnd.randint(0, 10**9)) + "-" + "%08X-%04X" % (rnd.getrandbits(32), rnd.getrandbits(16)),
             "at": round(1760000000 + rnd.random() * 10**7, 3)}
        if k in ("receive", "spend", "send"):
            e["peer"] = "%064x" % rnd.getrandbits(256)
        if k == "spend" and rnd.random() < 0.5:
            e["on"] = "post:" + str(rnd.randint(1, 10**6))
        out.append(e)
    return json.dumps(out, separators=(",", ":")).encode()


def inputs(d):
    rnd = random.Random(20261017)
    words = b"the coin of time a second minted once by its name montana book vault seed piece node row".split()
    sizes = [0, 1, 7, 8, 9, 100, 1000, 4095, 4096, 4097, 8191, 10000, 65536, 100000, 300000, 1 << 20]
    for s in sizes:
        (d / ("random-%d.bin" % s)).write_bytes(rnd.randbytes(s))
        (d / ("zeros-%d.bin" % s)).write_bytes(bytes(s))
        (d / ("pattern-%d.bin" % s)).write_bytes((b"abc" * (s // 3 + 1))[:s])
        text = bytearray()
        while len(text) < s:
            text += rnd.choice(words) + b" "
        (d / ("words-%d.bin" % s)).write_bytes(bytes(text[:s]))
        mixed = bytearray()
        while len(mixed) < s:
            mixed += rnd.randbytes(rnd.randint(1, 40)) if rnd.random() < 0.5 else bytes(text[:rnd.randint(1, 300)])
        (d / ("mixed-%d.bin" % s)).write_bytes(bytes(mixed[:s]))
    for n in [1, 2, 10, 37, 100, 1000, 8000]:
        (d / ("moves-%d.bin" % n)).write_bytes(moves(n, rnd))


def u32(b, i):
    return struct.unpack_from("<I", b, i)[0]


def u64(b, i):
    return struct.unpack_from("<Q", b, i)[0]


NBITS = [2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14, 2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14]
VALUE = [0, 2, 1, 4, 0, 3, 1, -1, 0, 2, 1, 5, 0, 3, 1, -1, 0, 2, 1, 6, 0, 3, 1, -1, 0, 2, 1, 7, 0, 3, 1, -1]


def as_v1(s):
    """The same stream with every bvx2 header laid as the bvx1 struct (lzfse_decode_v1, lzfse_decode_base.c 72-145)."""
    out, p, n = bytearray(), 0, 0
    while True:
        m = s[p:p + 4]
        if m == b"bvx$":
            return bytes(out + m), n
        if m == b"bvx-":
            k = u32(s, p + 4); out += s[p:p + 8 + k]; p += 8 + k; continue
        if m == b"bvxn":
            k = u32(s, p + 8); out += s[p:p + 12 + k]; p += 12 + k; continue
        assert m == b"bvx2", m
        v0, v1, v2 = u64(s, p + 8), u64(s, p + 16), u64(s, p + 24)
        f = lambda v, at, w: (v >> at) & ((1 << w) - 1)
        header = f(v2, 0, 32)
        lit_pay, lmd_pay = f(v0, 20, 20), f(v1, 40, 20)
        freq, q, acc, bits = [0] * 360, p + 32, 0, 0
        if q != p + header:
            for i in range(360):
                while q < p + header and bits + 8 <= 32:
                    acc |= s[q] << bits; bits += 8; q += 1
                c = acc & 31; nb = NBITS[c]
                freq[i] = 8 + ((acc >> 4) & 0xF) if nb == 8 else 24 + ((acc >> 4) & 0x3FF) if nb == 14 else VALUE[c]
                acc >>= nb; bits -= nb
        hdr = struct.pack("<IIIIIIIi4Hi3H", 0x31787662, u32(s, p + 4), lit_pay + lmd_pay, f(v0, 0, 20), f(v0, 40, 20), lit_pay, lmd_pay,
                          f(v0, 60, 3) - 7, f(v1, 0, 10), f(v1, 10, 10), f(v1, 20, 10), f(v1, 30, 10), f(v1, 60, 3) - 7,
                          f(v2, 32, 10), f(v2, 42, 10), f(v2, 52, 10)) + struct.pack("<360H", *freq) + b"\0\0"
        assert len(hdr) == 772
        out += hdr + s[p + header:p + header + lit_pay + lmd_pay]
        p += header + lit_pay + lmd_pay
        n += 1


def damaged(d):
    rnd = random.Random(1017)
    v1s = 0
    for ref in sorted(d.glob("*.ref")):
        s = ref.read_bytes()
        name = ref.name[:-4]
        if 64 < len(s):
            for k, cut in enumerate([1, 4, 8, len(s) // 3, len(s) // 2, len(s) - 5, len(s) - 1]):
                (d / ("%s.c%d.cut" % (name, k))).write_bytes(s[:cut])
            for k in range(4):
                b = bytearray(s); i = rnd.randrange(12, len(b) - 4); b[i] ^= 1 << rnd.randrange(8)
                (d / ("%s.f%d.cut" % (name, k))).write_bytes(bytes(b))
        v1, n = as_v1(s)
        if n:
            (d / (name + ".v1")).write_bytes(v1)
            v1s += 1
    print("damaged streams written, %d streams laid again as bvx1" % v1s)


if __name__ == "__main__":
    if sys.argv[1] == "--damage":
        damaged(Path(sys.argv[2]))
    else:
        inputs(Path(sys.argv[1]))
