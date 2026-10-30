#!/usr/bin/env python3
"""The keeping of a copy (iOS MTKeeping.swift), recomputed outside both apps from its formulas alone.

    python3 -I tools/keep_vectors.py

Reproduces every frozen value iOS checks before it keeps anything (MTKeepCode.agreesWithCanon, MTKeepDerive.agreesWithCanon,
MTKeepRing.agrees): the erasure code RS(16,12) over GF(256) with the modulus 0x11D and the Cauchy matrix
inverse((12 + i) XOR j), the slot secrets and the keeping key as HKDF-Expand(master_seed, info, 32), the light secret, the
82-byte head and its seal, and the ring of keepers. Android's Keeping.kt checks the same values on the phone; a value printed
here that differs from the one in the iOS source means a formula was misread.
"""
import hashlib
import hmac
import struct
import sys

CHUNK, GROUP, DATA = 868, 16, 12
PARITY = GROUP - DATA


def mul(a, b):
    p = 0
    for _ in range(8):
        if b & 1:
            p ^= a
        over = a & 0x80
        a = (a << 1) & 0xFF
        if over:
            a ^= 0x1D
        b >>= 1
    return p


TABLE = [[mul(a, b) for b in range(256)] for a in range(256)]


def inverse(a):
    for b in range(1, 256):
        if TABLE[a][b] == 1:
            return b
    raise ValueError(a)


CAUCHY = [[inverse((DATA + i) ^ j) for j in range(DATA)] for i in range(PARITY)]


def parity(blocks):
    width = len(blocks[0])
    out = []
    for i in range(PARITY):
        o = bytearray(width)
        for j in range(DATA):
            row = TABLE[CAUCHY[i][j]]
            b = blocks[j]
            for x in range(width):
                o[x] ^= row[b[x]]
        out.append(bytes(o))
    return out


def reconstruct(present):
    seen, taken = set(), []
    for p, b in present:
        if 0 <= p < GROUP and p not in seen:
            seen.add(p)
            taken.append((p, b))
            if len(taken) == DATA:
                break
    if len(taken) != DATA:
        return None
    width = len(taken[0][1])
    if all(p < DATA for p, _ in taken):
        out = [None] * DATA
        for p, b in taken:
            out[p] = b
        return out
    m = [[1 if c == p else 0 for c in range(DATA)] if p < DATA else list(CAUCHY[p - DATA]) for p, _ in taken]
    inv = [[1 if c == r else 0 for c in range(DATA)] for r in range(DATA)]
    for col in range(DATA):
        piv = next((r for r in range(col, DATA) if m[r][col]), None)
        if piv is None:
            return None
        m[col], m[piv] = m[piv], m[col]
        inv[col], inv[piv] = inv[piv], inv[col]
        iv = inverse(m[col][col])
        m[col] = [TABLE[iv][x] for x in m[col]]
        inv[col] = [TABLE[iv][x] for x in inv[col]]
        for r in range(DATA):
            if r != col and m[r][col]:
                f = m[r][col]
                m[r] = [m[r][x] ^ TABLE[f][m[col][x]] for x in range(DATA)]
                inv[r] = [inv[r][x] ^ TABLE[f][inv[col][x]] for x in range(DATA)]
    out = []
    for i in range(DATA):
        o = bytearray(width)
        for j in range(DATA):
            c = inv[i][j]
            if c:
                row = TABLE[c]
                b = taken[j][1]
                for x in range(width):
                    o[x] ^= row[b[x]]
        out.append(bytes(o))
    return out


def expand(master, info):   # HKDF-Expand(PRK = master_seed, info, 32): one block, T(1) = HMAC(PRK, info || 0x01)
    return hmac.new(master, info + b"\x01", hashlib.sha256).digest()


def slot_secret(master, k):
    return expand(master, b"mt-keep-slot\x00" + bytes([k]))


def keep_key(master):
    return expand(master, b"mt-keep-key")


def light_secret(master):
    return expand(master, b"mt-keep-light")


def domained(domain, *parts):
    return hashlib.sha256(domain.encode() + b"\x00" + b"".join(parts)).digest()


def tag(secret, window):
    return domained("mt-tag", secret, struct.pack("<Q", window))[:16]


def head(slot, n, generation, length, copy_digest, share_digest):
    return bytes([slot, n]) + struct.pack("<Q", generation) + struct.pack("<Q", length) + copy_digest + share_digest


def seal(key, head_bytes):
    return domained("mt-keep-seal", key, head_bytes)


def ring(place, of):
    q = min(of, GROUP)
    if q <= 0 or place < 0 or place >= of:
        return []
    j = place % q
    return [k for k in range(GROUP) if k % q == j or k % q == (j + 1) % q]


def main():
    ok = True

    def check(name, got, want):
        nonlocal ok
        good = got == want
        ok &= good
        print(("ok   " if good else "FAIL ") + name + " " + (got if isinstance(got, str) else repr(got)))

    body = [bytes([0xA0 + j]) * CHUNK for j in range(DATA)]
    par = parity(body)
    check("parity prefixes", ",".join(p[:4].hex() for p in par), "a5a5a5a5,acacacac,b7b7b7b7,bebebebe")
    check("parity digest", hashlib.sha256(b"".join(par)).hexdigest(), "8963024273fc41fdf9afe063f3be77e7fbc312a7d8ede4f96a7fd99dd4fd0e69")
    whole = body + par
    lost = {0, 5, 7, 11}
    check("rebuilt across 0,5,7,11", reconstruct([(i, b) for i, b in enumerate(whole) if i not in lost]) == body, True)
    counting = [bytes((j * 64 + x) % 251 for x in range(64)) for j in range(DATA)]
    cpar = parity(counting)
    loss = {3, 12, 13, 15}
    check("counting rebuilt across 3,12,13,15", reconstruct([(i, b) for i, b in enumerate(counting + cpar) if i not in loss]) == counting, True)

    master = bytes(range(64))
    check("slot 0", slot_secret(master, 0).hex(), "f57057fdd34a297a072f161d54105f98ec23cbbaf6229662b36efb9ae4aaa9d7")
    check("slot 1", slot_secret(master, 1).hex(), "c534306aa283d19c8e83f392bda37a7e59b7ccd7868b8df455bb9b6716e1ab91")
    check("slot 15", slot_secret(master, 15).hex(), "4573fb5ad5dc3b579049f304cc95cf5f3765ceaf07caab730d986c034788edab")
    check("tag of slot 3 at 1000", tag(slot_secret(master, 3), 1000).hex(), "ae67484d6abdb555a43159fc9386d753")
    key = keep_key(master)
    check("keep key", key.hex(), "9945bec54d8f26ab7859b3e6eb886456ff529fd2637aa2650626b3595e88970c")
    light = light_secret(master)
    check("light secret", light.hex(), "23d9bfa1a0151598ea710a15492cb9f8fcb46e5c86d39ba0e8824a69511a3776")
    check("light secret, seed backwards", light_secret(master[::-1]).hex(), "8d14528b640e1d7b114c2d299cf85f4ba7813a2308255dfba6025f01e4f288b9")
    check("tag of light at 1000", tag(light, 1000).hex(), "7b957934998d5c0ad69415e43616020c")
    h = head(2, 8, 0x1112131415161718, 0x0102030405060708, bytes(range(0x20, 0x40)), bytes(range(0x40, 0x60)))
    check("head length", len(h), 82)
    check("head seal", seal(key, h).hex(), "80b0b97f66a8ef64fce6d692935a82b37bf978c0e215cd8b190bb7a1100475ae")

    check("ring 0 of 4", ring(0, 4), [0, 1, 4, 5, 8, 9, 12, 13])
    check("ring 3 of 4", ring(3, 4), [0, 3, 4, 7, 8, 11, 12, 15])
    check("ring 0 of 1", ring(0, 1), list(range(16)))
    check("ring 1 of 2", ring(1, 2), list(range(16)))
    check("ring 16 of 20", ring(16, 20), [0, 1])
    check("ring 15 of 16", ring(15, 16), [0, 15])
    print("keep_vectors: " + ("all hold" if ok else "MISMATCH"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
