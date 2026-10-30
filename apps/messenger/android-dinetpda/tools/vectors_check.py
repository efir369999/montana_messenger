"""Independent recomputation of Android's own wire vectors (Pipes.kt pipeAgreesWithCanon) from the formula both apps
state: domained(domain, parts) = SHA-256(domain || 0x00 || parts...), windows as little-endian u64 (iOS MTPipe.windowLE)."""
import hashlib


def domained(domain, *parts):
    h = hashlib.sha256(domain.encode() + b"\x00")
    for p in parts:
        h.update(p)
    return h.digest()


def le8(w):
    return w.to_bytes(8, "little")


s32 = bytes(range(32))
pk = bytes((i * 7 + 3) % 256 for i in range(1952))
want = {
    "windowPos(s32, 0x0102030405060708)": (domained("mt-pos", s32, le8(0x0102030405060708)),
                                           "6f241143b5736f8ee9af63cd2db6fbf59b5bbc22069cc045307e8862e3ed6f8f"),
    "windowPos(s32, 1000)": (domained("mt-pos", s32, le8(1000)),
                             "db09ddb4cd56d677bd1f9fdc00a6894bc088b2cb8a382eaeb1f76644f2f95eec"),
    "overlayTag(pk1952)": (domained("mt-overlay", pk),
                           "f2c55658958eee8b961a4d63c2ec60a793cf9f22c373d115f3021523e3f0eabe"),
    # and three of the iOS frozen ones, to show the formula reproduces the iOS side as well
    "pipeTag(0x44*32, 1000)": (domained("mt-tag", b"\x44" * 32, le8(1000))[:16], "1d99467017fe1d0cc7c7ba29df6fd1b6"),
    "bodyKey(s32, 1000)": (hashlib.sha256(b"mt-pipe-key\x00" + s32 + le8(1000)).digest(),
                           "e25542e65a84d1a5b5c72a13172ecb62319c18f21a59978a53e7dac2c22a966a"),
    "ownerRef(0x99*32, 0x44*32)": (domained("mt-owner-ref", b"\x99" * 32, b"\x44" * 32)[:16], "f4f72dafb742470e49defbd3c2326c27"),
}
bad = 0
for name, (got, exp) in want.items():
    ok = got.hex() == exp
    bad += not ok
    print("%-38s %s %s" % (name, "OK  " if ok else "FAIL", got.hex()))
print("all agree" if not bad else "%d disagree" % bad)
