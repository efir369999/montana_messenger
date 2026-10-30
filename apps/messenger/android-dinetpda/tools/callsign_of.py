"""The call sign a twin reference stands for (Android Callsign.of, iOS MontanaCallsign): sum = sum*31 + byte over the
first 8 UTF-8 bytes of the reference, wrapping at 32 bits, then that row of callsigns.tsv.
    python -I tools/callsign_of.py <twin reference in hex> [en|ru|zh]"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE = os.path.join(HERE, "..", "app", "src", "main", "res", "raw", "callsigns.tsv")


def rows():
    out = []
    for line in open(TABLE, encoding="utf-8").read().split("\n"):
        if not line or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) >= 5:
            out.append({"en": f[1], "ru": f[2], "zh": f[4], "emoji": f[5] if len(f) >= 6 else ""})
    return out


def callsign(reference, lang="en"):
    t = rows()
    s = 0
    for b in reference.encode("utf-8")[:8]:
        s = (s * 31 + b) & 0xFFFFFFFF
    r = t[s % len(t)]
    word = r[lang]
    return (r["emoji"] + " " + word) if r["emoji"] else word


if __name__ == "__main__":
    print(callsign(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "en"))
