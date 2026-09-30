#!/usr/bin/env python3
# Re-checks the council walls' chains, WALL.jsonl and STUDENT.jsonl, link by link from genesis with the standard library
# alone. council.py imports these rules, so a stranger checks the very canon the master writes. A pass proves one unbroken
# chain whose open records re-hash from their bodies; a record's time and master stay its writer's word.
import datetime, hashlib, json, os, re, sys

FIELDS = ("n", "time", "master", "kind", "prev", "thread", "text")
KINDS = ("genesis", "word", "decision", "build", "agent", "state", "lesson", "open", "handover", "essence", "finding",
         "verdict")
ZERO = "0".zfill(64)
HEX = re.compile("[0-9a-f]{64}")
STAMP = "%Y-%m-%dT%H:%M:%SZ"
KEYS = frozenset(FIELDS + ("hash",))
# the Gematria Primus in its order: F U TH O R C G W H N I J EO P X S T B E M L NG OE D A AE Y IA EA
RUNES = (0x16A0, 0x16A2, 0x16A6, 0x16A9, 0x16B1, 0x16B3, 0x16B7, 0x16B9, 0x16BB, 0x16BE, 0x16C1, 0x16C4, 0x16C7, 0x16C8,
         0x16C9, 0x16CB, 0x16CF, 0x16D2, 0x16D6, 0x16D7, 0x16DA, 0x16DD, 0x16DF, 0x16DE, 0x16AA, 0x16AB, 0x16A3, 0x16E1,
         0x16E0)
# the essence of the TimeChain squeezed step by step: a step no shorter than the one above is no squeeze
LEVELS = ("paragraph", "phrase", "words", "word", "rune")
# a finding on an earlier master's code opens with its axis; another master rates it once, opening with + or -
AXES = ("elegance", "aesthetics", "security")
MARKS = ("+", "-")


def canonical(rec):
    body = dict((k, rec[k]) for k in FIELDS)
    return json.dumps(body, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def digest(rec):
    return hashlib.sha256(canonical(rec)).hexdigest()


def moment(stamp):
    try:
        return datetime.datetime.strptime(stamp, STAMP).strftime(STAMP) == stamp
    except (TypeError, ValueError):
        return False


def ladder(text):
    steps = text.split("\n")
    if len(steps) != len(LEVELS) or not all(s and s == s.strip() for s in steps):
        return "an essence is five lines, one per step: " + ", ".join(LEVELS)
    sizes = [len(s.encode("utf-8")) for s in steps]
    for level, above, size in zip(LEVELS[1:], sizes, sizes[1:]):
        if size not in range(above):
            return f"the {level} step is not shorter than the step above it"
    if len(steps[2].split()) == 1 or len(steps[3].split()) != 1:
        return "the words step holds a few words, the word step one"
    if len(steps[4]) != 1 or ord(steps[4]) not in RUNES:
        return "the rune step is one rune of the Gematria Primus"
    return None


def shape(r, closed_ok):
    if not isinstance(r, dict):
        return "not a JSON object"
    missing, extra = KEYS - set(r), set(r) - KEYS - ({"closed"} if closed_ok else set())
    if missing or extra:
        return "fields missing or unsealed: " + ", ".join(sorted(missing) + sorted(extra))
    if type(r["n"]) is not int:
        return "n is not an integer"
    if not moment(r["time"]):
        return "time is not a moment written YYYY-MM-DDTHH:MM:SSZ"
    if not all(isinstance(r[k], str) and r[k].strip() for k in ("master", "kind")) or not isinstance(r["text"], str):
        return "master and kind are named, text is a string"
    if r["kind"] not in KINDS:
        return f"kind {r['kind']} is not one of " + ", ".join(KINDS)
    hashes = [r["prev"], r["hash"]] + (r["thread"] if isinstance(r["thread"], list) else [None])
    if not all(isinstance(h, str) and HEX.fullmatch(h) for h in hashes):
        return "prev, hash and every thread entry are 64 lowercase hex digits"
    if len(set(r["thread"])) != len(r["thread"]):
        return "thread names one record twice"
    if "closed" in r and (r["closed"] is not True or r["text"]):
        return "a closed record carries closed = true and no text"
    return None


def link(r, i, prev, last, past):
    if r["n"] != i:
        return f"numbered {r['n']}"
    if max(r["time"], last) != r["time"]:
        return f"its time runs back before record {i - 1}"
    if r["prev"] != prev:
        return "prev does not name the record before it"
    if not r.get("closed") and digest(r) != r["hash"]:
        return "its hash does not match its body"
    if not set(r["thread"]).issubset(past):
        return "its thread points outside the past"
    return None


def opening(r):
    return "" if r.get("closed") else re.match("[a-z]*", r["text"].lstrip()).group(0)


def rule(r, past):
    shut = r.get("closed")
    if r["kind"] == "essence":
        before = [h for h, q in past.items() if q["kind"] == "essence"][-1:]
        why = None if shut else ladder(r["text"])
        if why or not set(before).issubset(r["thread"]):
            return why or "a re-squeezed essence threads to the essence before it"
    if r["kind"] == "finding" and not shut and opening(r) not in AXES:
        return "a finding opens with its axis: " + ", ".join(AXES)
    if r["kind"] == "verdict":
        found = [past[h] for h in r["thread"] if past[h]["kind"] == "finding"]
        if len(found) != 1:
            return "a verdict threads to one finding"
        if found[0]["master"] == r["master"]:
            return "a master does not rate his own finding"
        if any(q["kind"] == "verdict" and q["master"] == r["master"] and found[0]["hash"] in q["thread"] for q in past.values()):
            return "a master rates a finding once"
        if not shut and r["text"].lstrip()[:1] not in MARKS:
            return "a verdict opens with + or -"
    return None


def check(recs, closed_ok=True):
    prev, past, last, shut = ZERO, {}, "", 0
    for i, r in enumerate(recs):
        bad = shape(r, closed_ok) or link(r, i, prev, last, past) or rule(r, past)
        if bad:
            return f"record {i}: {bad}", shut
        shut += bool(r.get("closed"))
        past[r["hash"]] = r
        prev, last = r["hash"], r["time"]
    return None, shut


def read(path):
    return [json.loads(row) for row in open(path, encoding="utf-8") if row.strip()]


def main(paths):
    here = os.path.dirname(os.path.abspath(__file__))
    paths = paths or [os.path.join(here, f) for f in ("WALL.jsonl", "STUDENT.jsonl") if os.path.exists(os.path.join(here, f))]
    if not paths:
        print("usage: python3 verify.py [WALL.jsonl] [STUDENT.jsonl]")
        return 2
    broken = 0
    for path in paths:
        recs = []
        try:
            recs = read(path)
            bad, shut = check(recs)
        except (OSError, ValueError) as e:
            bad, shut = f"unreadable: {e}", 0
        name = os.path.basename(path)
        if bad:
            broken = 1
            print(f"{name}: BROKEN -- {bad}")
        else:
            print(f"{name}: holds -- {len(recs)} records from genesis, {shut} closed, head {recs[-1]['hash'] if recs else ZERO}")
    return broken


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
