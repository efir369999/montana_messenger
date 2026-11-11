#!/usr/bin/env python3
"""Compare two static libraries member by member, setting aside what only names the build.

usage: python3 tools/compare-archives.py MINE.a THEIRS.a

A build from a clone does not give the shipped archive's SHA-256: the archive names the machine and the hour that built it
(OpenSSL's ENGINESDIR, MODULESDIR and "built on"; the crates' build hashes in member and symbol names; LLVM's .llvm.N
suffixes of promoted local symbols). Every member is paired by its name with the build hash taken out and its Mach-O read:
the bytes of every section must be equal, and its symbol names equal once those hashes are set aside. OpenSSL's two
configuration objects may differ only in the strings that name the build directory and the hour. Exit 0 when all hold.
"""
import hashlib, re, struct, sys

HASH = re.compile(rb"-[0-9a-f]{16}[.]")
LLVM = re.compile(rb"[.]llvm[.][0-9]+")
BUILD_DIR = re.compile(rb"/[ -~]*?/out/openssl-build/install")
BUILT_ON = re.compile(rb"built on: [ -~]*")
OPENSSL_CONFIG = ("libcrypto-lib-cversion.o", "libcrypto-lib-defaults.o")


def members(path):
    b = open(path, "rb").read()
    out, i = {}, 8
    while i + 60 <= len(b):
        name = b[i:i + 16].decode("latin1").strip()
        size = int(b[i + 48:i + 58].decode().strip())
        body = b[i + 60:i + 60 + size]
        if name.startswith("#1/"):
            n = int(name[3:])
            name, body = body[:n].rstrip(bytes(1)).decode("latin1"), body[n:]
        if name != "__.SYMDEF" and not name.startswith("__.SYMDEF"):
            out.setdefault(HASH.sub(b".", name.encode()).decode(), []).append(body)
        i += 60 + size + (size % 2)
    return out


def macho(body):
    """The bytes of every section and the sorted symbol names, hashes set aside."""
    ncmds = struct.unpack_from("<I", body, 16)[0]
    off, sections, names = 32, [], []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", body, off)
        if cmd == 0x19:   # LC_SEGMENT_64
            nsects = struct.unpack_from("<I", body, off + 64)[0]
            for k in range(nsects):
                s = off + 72 + 80 * k
                sect, seg = body[s:s + 16].rstrip(bytes(1)), body[s + 16:s + 32].rstrip(bytes(1))
                sz, fo = struct.unpack_from("<Q", body, s + 40)[0], struct.unpack_from("<I", body, s + 48)[0]
                flags = struct.unpack_from("<I", body, s + 64)[0]
                data = b"" if (flags & 0xff) == 1 or not fo else body[fo:fo + sz]   # S_ZEROFILL has no bytes
                sections.append((seg + b"," + sect, data))
        elif cmd == 0x2:   # LC_SYMTAB
            symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", body, off + 8)
            strtab = body[stroff:stroff + strsize]
            for k in range(nsyms):
                strx = struct.unpack_from("<I", body, symoff + 16 * k)[0]
                name = strtab[strx:strtab.index(bytes(1), strx)]
                names.append(LLVM.sub(b".llvm.N", HASH.sub(b".", name)))
        off += size
    return sections, sorted(names)


def same(name, a, b):
    if a == b:
        return True
    sa, na = macho(a)
    sb, nb = macho(b)
    if name in OPENSSL_CONFIG:   # only the strings naming the build directory and the hour may differ
        text = lambda v: BUILT_ON.sub(b"built on", BUILD_DIR.sub(b"BUILD", v))
    else:
        text = lambda v: LLVM.sub(b".llvm.N", HASH.sub(b".", v))
    norm = lambda secs: [(k, text(v) if b"cstring" in k else v) for k, v in secs]
    return na == nb and norm(sa) == norm(sb)


def main(mine, theirs):
    a, b = members(mine), members(theirs)
    for path in (mine, theirs):
        print("sha256", hashlib.sha256(open(path, "rb").read()).hexdigest(), path)
    if sorted(a) != sorted(b):
        print("DIFFERENT: member names", sorted(set(a).symmetric_difference(b))[:12])
        return 1
    bad = [n for n in sorted(a) if len(a[n]) != len(b[n]) or not all(same(n, x, y) for x, y in zip(sorted(a[n], key=len), sorted(b[n], key=len)))]
    exact = sum(1 for n in a if sorted(a[n]) == sorted(b[n]))
    print("members", len(a), "byte-equal", exact, "equal but for the build's names", len(a) - exact - len(bad), "different", len(bad))
    for n in bad:
        print("  DIFFERENT", n)
    print("SAME CODE" if not bad else "DIFFERENT CODE")
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
