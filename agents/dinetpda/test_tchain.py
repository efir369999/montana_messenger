"""Tests of tchain.py (issue #30). From the repository root: python -m unittest discover -s agents/dinetpda -v"""

import contextlib
import hashlib
import io
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import unicodedata
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tchain  # noqa: E402

CHAIR = "Claude of DinetPDA #1 [aaaaaaaa]"
NEXT_CHAIR = "Claude of DinetPDA #2 [bbbbbbbb]"
HELPER = "subagent of DinetPDA #1 [cccccccc]"
VARIABLES = ("TCHAIN_HOME", "TCHAIN_ACCEPT", "TCHAIN_HANDOVER", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CONFIG_DIR")


def definition_hash(record):
    """The hash as issue #30 defines it, computed here without tchain: SHA-256 over the record's JSON with sorted keys,
    every field but hash, prev included."""
    body = {key: value for key, value in record.items() if key != "hash"}
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
                          .encode("utf-8")).hexdigest()


@contextlib.contextmanager
def working_directory(path):
    before = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(before)


class ChainCase(unittest.TestCase):
    """A fresh data folder in a temporary directory, and an environment without tchain's or Claude Code's variables."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home"
        environment = mock.patch.dict(os.environ)
        environment.start()
        self.addCleanup(environment.stop)
        for name in VARIABLES:
            os.environ.pop(name, None)

    def cli(self, *argv, home=True):
        """Run the command line in this process: (exit code, stdout, stderr)."""
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                code = tchain.main(list(argv) + (["--home", str(self.home)] if home else []))
            except SystemExit as exit_:  # argparse refuses a misused command this way
                code = exit_.code
        return code, out.getvalue(), err.getvalue()

    def ok(self, *argv):
        code, out, err = self.cli(*argv)
        self.assertEqual(code, 0, msg=f"{argv}: {err or out}")
        return out

    def refused(self, *argv):
        code, out, err = self.cli(*argv)
        self.assertEqual(code, 2, msg=f"{argv} was not refused: {out}")
        return err

    def lines(self, name=tchain.CHAIN_FILE):
        return (self.home / name).read_bytes().split(b"\n")[:-1]

    def write_lines(self, lines, name=tchain.CHAIN_FILE):
        (self.home / name).write_bytes(b"".join(line + b"\n" for line in lines))

    def records(self, name=tchain.CHAIN_FILE):
        return [json.loads(line) for line in self.lines(name)]

    def add(self, text, signature=CHAIR):
        return self.ok("add", text, "--from", signature)

    def append_past_the_tool(self, *texts, signature=CHAIR):
        """Append correctly hashed links by hand, at the current time, as a hand with write access could."""
        lines = self.lines()
        for text in texts:
            record = {"n": len(lines), "time": tchain.utc_now(), "task": text, "from": signature,
                      "prev": json.loads(lines[-1])["hash"]}
            record["hash"] = tchain.seal(record)
            lines.append(tchain.canonical(record))
        self.write_lines(lines)


class TheLink(ChainCase):
    """A: one move is one record; its hash covers every field but itself, prev included."""

    def test_append_then_verify_recomputes_from_the_genesis(self):
        for i in range(3):
            self.add(f"move {i}")
        out = self.ok("verify")
        self.assertIn("ok: 3 links, 0 to 2", out)
        prev = "0" * 64
        for n, line in enumerate(self.lines()):
            record = json.loads(line)
            self.assertEqual(set(record), {"n", "time", "task", "from", "prev", "hash"})
            self.assertEqual((record["n"], record["prev"], record["from"]), (n, prev, CHAIR))
            self.assertEqual(record["hash"], definition_hash(record))
            self.assertEqual(line, json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
                             .encode("utf-8"))
            self.assertRegex(record["time"], r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
            prev = record["hash"]
        self.assertIn(f"head {prev}", out)
        self.assertNotIn(b"\r", (self.home / tchain.CHAIN_FILE).read_bytes())

    def test_the_hash_is_pinned_by_a_vector(self):
        genesis = {"n": 0, "time": "2026-10-25T15:00:00Z", "task": "Принято: the genesis",
                   "from": "Claude of DinetPDA #1 [5ca1ab1e]", "prev": "0" * 64}
        vector = "19b4f08b059ce47c34477df1d68f1b43b15a8d7ca4b8c65c2feb4255bedfcf0a"
        self.assertEqual(definition_hash(genesis), vector)
        self.assertEqual(tchain.seal(genesis), vector)
        self.assertEqual(tchain.seal(dict(genesis, hash="anything")), vector)

    def test_non_ascii_is_written_as_itself(self):
        self.add("звено № 1")
        self.assertIn("звено № 1".encode("utf-8"), self.lines()[0])

    def test_a_task_is_one_line_of_at_most_280_characters(self):
        self.add("x" * 280)
        for text in ("x" * 281, "two\nlines", "a\ttab", "   "):
            self.refused("add", text, "--from", CHAIR)
        self.assertEqual(len(self.lines()), 1)

    def test_a_signature_is_name_number_and_an_8_hex_label(self):
        for signature in ("Claude", "Claude #1", "Claude [aaaaaaaa]", "Claude #1 [AAAAAAAA]", "Claude #1 [aaaaaaa]",
                          "Claude #0 [aaaaaaaa]", " Claude #1 [aaaaaaaa]", "Cl#aude #1 [aaaaaaaa]", "Claude #01 [aaaaaaaa]"):
            self.refused("add", "x", "--from", signature)
        self.assertFalse((self.home / tchain.CHAIN_FILE).exists())

    def test_recent_prints_the_last_n_links(self):
        for i in range(20):
            self.add(f"move {i}")
        out = self.ok("recent", "3").splitlines()
        self.assertEqual([line.split(": ", 1)[1] for line in out], ["move 17", "move 18", "move 19"])
        self.assertEqual(len(self.ok("recent").splitlines()), 13)
        self.assertEqual(self.ok("recent", "0"), "")

    def test_an_empty_chain_verifies(self):
        self.assertIn("holds no link yet", self.ok("verify"))

    def test_a_one_line_text_holds_no_separator_or_right_to_left_mark(self):
        for mark in ("\N{LINE SEPARATOR}", "\N{PARAGRAPH SEPARATOR}", "\N{RIGHT-TO-LEFT OVERRIDE}",
                     "\N{RIGHT-TO-LEFT MARK}", "\N{ARABIC LETTER MARK}", "\N{FIRST STRONG ISOLATE}", chr(0x85)):
            with self.subTest(mark=hex(ord(mark))):
                self.assertIn("holds the character", self.refused("add", f"a{mark}b c", "--from", CHAIR))
                self.refused("add", "x", "--from", f"Claude{mark} #1 [aaaaaaaa]")
        self.add("a family \N{MAN}\N{ZERO WIDTH JOINER}\N{WOMAN}: a joiner reorders nothing")
        self.assertEqual(len(self.lines()), 1)
        marks = {chr(c) for c in (0x2028, 0x2029, 0x061C, 0x200E, 0x200F, *range(0x202A, 0x202F),
                                  *range(0x2066, 0x206A))}
        controls = {chr(c) for c in range(0x10000) if unicodedata.category(chr(c)) == "Cc"}
        refused = {chr(c) for c in range(0x10000) if tchain.ONE_LINE_ODD.fullmatch(chr(c))}
        self.assertEqual(refused, controls | marks)
        self.assertEqual({c for c in refused if tchain.LINES_ODD.fullmatch(c)}, refused - {"\n", "\t"})

    def test_a_signature_is_at_most_100_characters(self):
        tail = " #1 [aaaaaaaa]"
        self.add("x", "N" * (tchain.SIGNATURE_LIMIT - len(tail)) + tail)
        self.assertIn("the limit is 100", self.refused("add", "x", "--from", "N" * tchain.SIGNATURE_LIMIT + tail))
        self.assertLess(len(self.refused("add", "x", "--from", "#" * 2000)), 300)  # the message quotes it clipped
        self.append_past_the_tool("x", signature="N" * 2000 + tail)
        code, out, _ = self.cli("verify")
        self.assertEqual(code, 1)
        self.assertIn("broken at n=1: the signature has 2014 characters; the limit is 100", out)

    def test_a_writer_waits_for_the_lock_and_gives_up_only_after_lock_wait(self):
        self.assertGreaterEqual(tchain.LOCK_WAIT, 60)
        chain = tchain.Chain(self.home / tchain.CHAIN_FILE, tchain.check_link)
        held, release = threading.Event(), threading.Event()

        def hold():
            with chain._locked():
                held.set()
                release.wait(10)

        holder = threading.Thread(target=hold)
        holder.start()
        try:
            self.assertTrue(held.wait(10))
            with mock.patch.object(tchain, "LOCK_WAIT", 0.2), self.assertRaises(tchain.Refused) as refusal:
                chain.append({"task": "too early", "from": CHAIR})
            self.assertIn("another writer has held chain.jsonl", str(refusal.exception))
            threading.Timer(0.3, release.set).start()
            chain.append({"task": "after the holder", "from": CHAIR})  # it waits for the lock, then writes
        finally:
            release.set()
            holder.join()
        self.assertEqual([record["task"] for record in chain.read()[0]], ["after the holder"])

    def test_two_writers_at_once_keep_one_chain(self):
        chain = tchain.Chain(self.home / tchain.CHAIN_FILE, tchain.check_link)
        errors = []

        def write(signature):
            try:
                for i in range(15):
                    chain.append({"task": f"move {i}", "from": signature})
            except Exception as error:  # noqa: BLE001 -- reported below
                errors.append(error)

        writers = [threading.Thread(target=write, args=(signature,)) for signature in (CHAIR, HELPER)]
        for writer in writers:
            writer.start()
        for writer in writers:
            writer.join()
        self.assertEqual(errors, [])
        records, broken = chain.read()
        self.assertIsNone(broken)
        self.assertEqual(len(records), 30)


class Tampering(ChainCase):
    """A: any change to a written link makes verify fail, and verify names the first broken n."""

    def setUp(self):
        super().setUp()
        for i in range(6):
            self.add(f"move {i}")
        self.original = self.lines()

    def broken_at(self, n):
        code, out, _ = self.cli("verify")
        self.assertEqual(code, 1, out)
        self.assertIn(f"broken at n={n}:", out)
        return out

    def rewrite(self, n, **fields):
        lines = list(self.original)
        lines[n] = tchain.canonical(dict(json.loads(lines[n]), **fields))
        self.write_lines(lines)

    def test_a_task(self):
        self.rewrite(3, task="another move")
        self.assertIn("hash does not match", self.broken_at(3))

    def test_a_time(self):
        self.rewrite(3, time="2026-01-01T00:00:00Z")
        self.broken_at(3)

    def test_a_signature(self):
        self.rewrite(3, **{"from": NEXT_CHAIR})
        self.broken_at(3)

    def test_a_prev(self):
        self.rewrite(3, prev="f" * 64)
        self.assertIn("prev is not the hash of link 2", self.broken_at(3))

    def test_the_genesis_prev(self):
        self.rewrite(0, prev="1" * 64)
        self.assertIn("64 zeros", self.broken_at(0))

    def test_a_hash(self):
        self.rewrite(3, hash="e" * 64)
        self.broken_at(3)

    def test_a_deleted_record(self):
        self.write_lines(self.original[:3] + self.original[4:])
        self.assertIn("n is 4 where 3 stands", self.broken_at(3))

    def test_reordered_records(self):
        lines = list(self.original)
        lines[3], lines[4] = lines[4], lines[3]
        self.write_lines(lines)
        self.broken_at(3)

    def test_an_inserted_record(self):
        self.write_lines(self.original[:3] + [self.original[2]] + self.original[3:])
        self.broken_at(3)

    def test_a_link_resealed_after_a_change_is_caught_by_the_next(self):
        record = dict(json.loads(self.original[3]), task="another move")
        record["hash"] = tchain.seal(record)
        lines = list(self.original)
        lines[3] = tchain.canonical(record)
        self.write_lines(lines)
        self.assertIn("prev is not the hash of link 3", self.broken_at(4))

    def test_a_cut_tail_is_caught_by_an_anchor(self):
        head = json.loads(self.original[5])["hash"]
        self.write_lines(self.original[:4])
        self.assertEqual(self.cli("verify")[0], 0)  # what is left is still a whole chain
        code, out, _ = self.cli("verify", "--anchor", f"5:{head}")
        self.assertEqual(code, 1)
        self.assertIn("ends at n=3", out)
        self.write_lines(self.original)
        self.assertIn("matches the anchor", self.ok("verify", "--anchor", f"5:{head}"))

    def test_a_line_not_in_canonical_form(self):
        lines = list(self.original)
        lines[2] = lines[2].replace(b'","', b'", "', 1)
        self.write_lines(lines)
        self.assertIn("not the canonical JSON", self.broken_at(2))

    def test_a_cut_write(self):
        data = b"".join(line + b"\n" for line in self.original)
        (self.home / tchain.CHAIN_FILE).write_bytes(data[:-10])
        self.broken_at(5)
        (self.home / tchain.CHAIN_FILE).write_bytes(data[:-1])
        self.assertIn("no line end", self.broken_at(5))

    def test_a_line_that_is_not_json(self):
        self.write_lines(self.original[:2] + [b"edited by hand"] + self.original[3:])
        self.broken_at(2)

    def test_crlf_line_ends_change_no_field(self):
        (self.home / tchain.CHAIN_FILE).write_bytes(b"".join(line + b"\r\n" for line in self.original))
        self.ok("verify")

    def test_nothing_is_written_to_a_broken_chain(self):
        self.rewrite(2, task="changed")
        before = (self.home / tchain.CHAIN_FILE).read_bytes()
        self.assertIn("broken at n=2", self.refused("add", "one more", "--from", CHAIR))
        self.assertEqual((self.home / tchain.CHAIN_FILE).read_bytes(), before)

    def test_a_line_nested_too_deep_is_a_broken_link_not_a_crash(self):
        self.write_lines(self.original[:3] + [b"[" * 200_000])
        self.assertIn("not JSON", self.broken_at(3))
        self.assertIn("broken at n=3", self.refused("add", "one more", "--from", CHAIR))
        self.assertIn("BROKEN at n=3", self.ok("start"))

    def test_time_runs_forward(self):
        records = [json.loads(line) for line in self.original]
        records[3]["time"] = "2001-01-01T00:00:00Z"
        for record in records[3:]:  # resealed from link 3 on, as a forger would
            record["prev"] = records[record["n"] - 1]["hash"]
            record["hash"] = tchain.seal(record)
        self.write_lines([tchain.canonical(record) for record in records])
        self.assertIn("its time 2001-01-01T00:00:00Z is earlier than", self.broken_at(3))
        self.write_lines(self.original)
        with mock.patch.object(tchain, "utc_now", return_value="2001-01-01T00:00:00Z"):  # a clock gone back
            self.assertIn("is earlier than", self.refused("add", "one more", "--from", CHAIR))
        self.assertEqual(self.lines(), self.original)

    def test_repair_finishes_a_cut_write_and_nothing_else(self):
        path, data = self.home / tchain.CHAIN_FILE, b"".join(line + b"\n" for line in self.original)
        path.write_bytes(data[:-10])  # part of link 5
        self.assertIn("repair finishes the cut write", self.broken_at(5))
        self.assertIn("repair finishes the cut write", self.refused("add", "one more", "--from", CHAIR))
        self.assertIn("write nothing before repair finishes the cut write", self.ok("start"))
        self.assertIn("removed the cut write of link 5", self.ok("repair"))
        self.assertEqual(self.lines(), self.original[:5])
        path.write_bytes(data[:-1])  # link 5 whole but for its line end
        self.assertIn("link 5 was whole but for its line end", self.ok("repair"))
        self.assertEqual(path.read_bytes(), data)
        self.assertIn("needs no repair", self.ok("repair"))
        self.rewrite(2, task="changed")  # a break that is no cut write
        before = path.read_bytes()
        self.assertIn("restore the file from a copy", self.refused("repair"))
        self.assertEqual(path.read_bytes(), before)


class Windows(ChainCase):
    """B: 13 links make a window; a full window is sealed by the chairman's next signed link and by no other."""

    def fill(self, count, signature=CHAIR):
        for i in range(count):
            self.add(f"move {i}", signature)

    def test_a_full_window_is_sealed_by_the_chairmans_next_link_only(self):
        self.add("Accepted: start read; taking the first task")  # link 0 makes CHAIR the chairman
        self.fill(11)
        self.assertIn("window 0: links 0 to 11, 12 of 13: open", self.ok("windows"))
        self.assertIn("window 0 is full", self.add("the thirteenth link"))  # link 12 fills window 0
        self.assertIn("window 0: links 0 to 12, full, not sealed", self.ok("windows"))
        self.assertNotIn("seals", self.add("a helper's move", HELPER))  # link 13 is not the chairman's
        self.assertIn("window 0: links 0 to 12, full, not sealed", self.ok("windows"))
        self.assertIn("seals window 0 (links 0 to 12)", self.add("the chairman's move"))  # link 14
        out = self.ok("windows")
        self.assertIn(f"window 0: links 0 to 12, full, sealed by link 14 ({CHAIR})", out)
        self.assertIn("window 1: links 13 to 14, 2 of 13: open", out)
        self.assertIn(f"chairman: {CHAIR}, accepted at link 0", out)

    def test_without_the_acceptance_words_no_window_closes(self):
        self.fill(30)
        out = self.ok("windows")
        self.assertIn("window 0: links 0 to 12, full, not sealed", out)
        self.assertIn("window 1: links 13 to 25, full, not sealed", out)
        self.assertIn("window 2: links 26 to 29, 4 of 13: open", out)
        self.assertIn('chairman: none -- no link begins with "Accepted"', out)

    def test_the_chairman_is_whoever_last_wrote_the_acceptance_words(self):
        self.add("Accepted: the first session", CHAIR)  # link 0
        self.fill(12, HELPER)  # links 1 to 12 fill window 0
        self.add("Accepted: handover of agent 1", NEXT_CHAIR)  # link 13: the new chairman's first link seals it
        self.fill(12, CHAIR)  # links 14 to 25, by the chairman before, seal nothing
        out = self.ok("windows")
        self.assertIn(f"window 0: links 0 to 12, full, sealed by link 13 ({NEXT_CHAIR})", out)
        self.assertIn("window 1: links 13 to 25, full, not sealed", out)
        self.assertIn(f"chairman: {NEXT_CHAIR}, accepted at link 13", out)
        self.add("the chairman's move", NEXT_CHAIR)  # link 26
        self.assertIn(f"window 1: links 13 to 25, full, sealed by link 26 ({NEXT_CHAIR})", self.ok("windows"))

    def test_the_words_begin_the_link_whole_and_in_their_case(self):
        for text in ("Accepted: x", "Accepted", "Accepted, taking item 12"):
            self.assertTrue(tchain.begins_with(text, "Accepted"), text)
        for text in ("Acceptedly", "accepted: x", "Not Accepted", "Accepted_x", " Accepted"):
            self.assertFalse(tchain.begins_with(text, "Accepted"), text)

    def test_the_words_are_the_same_for_every_reader(self):
        os.environ["TCHAIN_ACCEPT"] = "Принял"  # read by no command
        self.add("Принял: start read")
        self.fill(13)
        out = self.ok("windows")
        self.assertIn("full, not sealed", out)
        self.assertIn('chairman: none -- no link begins with "Accepted"', out)
        for option in ("--accept", "--handover"):  # no command takes other words
            self.assertEqual(self.cli("windows", option, "Принял")[0], 2)
            self.assertEqual(self.cli("add", "x", "--from", CHAIR, option, "[task")[0], 2)
        self.add("Accepted: start read", CHAIR)
        self.ok("task", "add", "first", "--issue", "efir369999/montana_messenger#30", "--deadline",
                "2099-01-01T15:00:00Z", "--from", CHAIR)
        self.add("Принял: start read", NEXT_CHAIR)  # not an acceptance link: CHAIR stays the chairman
        self.assertIn("only the chairman", self.refused("task", "add", "second", "--issue",
                                                        "efir369999/montana_messenger#30", "--deadline",
                                                        "2099-01-01T15:00:00Z", "--from", NEXT_CHAIR))
        self.assertEqual(sum(" born: " in record["task"] for record in self.records()), 1)


class TheConstitution(ChainCase):
    """C: a second chain of the same envelope; only a link carrying the Author's word changes the standing text."""

    def const(self, *argv):
        return self.ok("const", *argv)

    def state(self):
        chain = tchain.Chain(self.home / tchain.CONSTITUTION_FILE, tchain.check_constitution_link)
        records, broken = chain.read()
        return tchain.constitution(records), broken

    def standing(self):
        return {number: record["text"] for number, record in self.state()[0].articles.items()}

    def forge(self, **fields):
        """Append a correctly hashed link past the tool, as a hand with write access could."""
        lines = self.lines(tchain.CONSTITUTION_FILE)
        now = tchain.utc_now()
        record = dict({"n": len(lines), "time": now, "from": CHAIR, "prev": json.loads(lines[-1])["hash"],
                       "word_time": now}, **fields)
        record = {key: value for key, value in record.items() if value is not None}
        record["hash"] = tchain.seal(record)
        self.write_lines(lines + [tchain.canonical(record)], tchain.CONSTITUTION_FILE)

    def test_articles_are_set_replaced_and_removed_by_the_authors_word(self):
        self.const("article", "0", "Elegance. Aesthetics. Security.", "--word", "/// put it first", "--from", CHAIR)
        self.const("article", "-3", "Time is the metadata of reality.", "--word", "/// yes", "--from", CHAIR)
        self.const("article", "1", "The agent wins time.", "--word", "/// yes", "--from", CHAIR)
        self.const("article", "1", "The agent wins time for the Author.", "--word", "/// for me", "--from", CHAIR)
        self.const("remove", "0", "--word", "/// drop it", "--from", CHAIR)
        self.assertEqual(self.standing(), {-3: "Time is the metadata of reality.", 1: "The agent wins time for the Author."})
        out = self.const("show")
        self.assertIn("2 articles standing", out)
        self.assertLess(out.index("-3. Time is"), out.index("1. The agent wins time for the Author."))
        self.assertIn("ok: 5 links", self.const("verify"))
        records = self.records(tchain.CONSTITUTION_FILE)
        self.assertEqual([record["op"] for record in records], ["article"] * 4 + ["remove"])
        self.assertEqual(set(records[4]), {"n", "time", "from", "prev", "hash", "op", "no", "word", "word_time"})
        self.assertEqual(records[0]["prev"], "0" * 64)
        self.assertEqual(len(self.const("log").splitlines()), 5)

    def test_the_word_is_kept_verbatim_with_its_time(self):
        word = "/// да\n  to both questions  "
        self.const("article", "2", "text", "--word", word, "--word-time", "2026-01-02T10:58:00Z", "--from", CHAIR)
        record = self.records(tchain.CONSTITUTION_FILE)[0]
        self.assertEqual((record["word"], record["word_time"]), (word, "2026-01-02T10:58:00Z"))
        self.refused("const", "article", "2", "text", "--word", "w", "--word-time", "2099-01-01T00:00:00Z",
                     "--from", CHAIR)
        self.refused("const", "article", "2", "text", "--word", "w", "--word-time", "25.10.2026 10:58", "--from", CHAIR)

    def test_the_word_from_a_file_or_standard_input(self):
        path = Path(self.tmp.name) / "word.txt"
        path.write_bytes("\ufeff/// да\r\nsecond line\r\n".encode("utf-8"))
        self.const("article", "4", "text", "--word-file", str(path), "--from", CHAIR)
        stdin = io.TextIOWrapper(io.BytesIO("/// нет\n".encode("utf-8")), encoding="utf-8")
        with mock.patch.object(sys, "stdin", stdin):
            self.const("article", "4", "text two", "--word-file", "-", "--from", CHAIR)
        words = [record["word"] for record in self.records(tchain.CONSTITUTION_FILE)]
        self.assertEqual(words, ["/// да\r\nsecond line", "/// нет"])
        self.refused("const", "article", "4", "text", "--word", "w", "--word-file", str(path), "--from", CHAIR)

    def test_without_the_authors_word_nothing_changes(self):
        self.const("article", "0", "Elegance.", "--word", "/// yes", "--from", CHAIR)
        self.refused("const", "article", "0", "Changed.", "--from", CHAIR)
        self.refused("const", "article", "0", "Changed.", "--word", "  ", "--from", CHAIR)
        self.refused("const", "remove", "0", "--from", CHAIR)
        self.assertEqual(self.standing(), {0: "Elegance."})
        before = self.lines(tchain.CONSTITUTION_FILE)
        for word in ("", None):  # an empty word, and no word at all, written past the tool with a correct hash
            with self.subTest(word=word):
                self.write_lines(before, tchain.CONSTITUTION_FILE)
                self.forge(op="article", no=0, text="Changed.", word=word)
                state, broken = self.state()
                self.assertEqual(broken.n, 1)
                self.assertEqual({n: r["text"] for n, r in state.articles.items()}, {0: "Elegance."})
                self.assertIn("broken at n=1", self.cli("const", "verify")[1])
                self.assertIn("broken at n=1", self.refused("const", "article", "0", "Again.", "--word", "/// yes",
                                                            "--from", CHAIR))

    def test_the_line_of_decisions(self):
        out = self.const("decide", "Shall a window close by a quorum of the living?", "--word",
                         "Gate 0: the consensus is his to choose", "--from", CHAIR)
        self.assertIn("place 1 of the line of decisions", out)
        self.assertIn("place 2", self.const("decide", "Shall the ports walk by day?", "--word",
                                            "the exception names the iOS client only", "--from", CHAIR))
        self.const("decided", "1", "--word", "/// да", "--word-time", "2026-01-02T10:58:00Z", "--from", CHAIR)
        self.assertIn("decided at link 2", self.refused("const", "decided", "1", "--word", "/// again", "--from", CHAIR))
        self.assertIn("no place 3", self.refused("const", "decided", "3", "--word", "/// ?", "--from", CHAIR))
        state, broken = self.state()
        self.assertIsNone(broken)
        self.assertEqual([place["answer"] is None for place in state.line], [False, True])
        self.assertEqual(state.line[0]["answer"]["word"], "/// да")
        self.assertEqual(state.articles, {})  # an answer is not an article: the Author's article link changes the text
        show = self.const("show")
        self.assertIn("line of decisions: 2 places, 1 open", show)
        self.assertIn("1. decided at link 2 by the Author's word of 2026-01-02T10:58:00Z", show)
        self.assertIn("2. open since link 1: Shall the ports walk by day?", show)

    def test_a_link_out_of_order_changes_nothing(self):
        self.const("article", "5", "Build the Economy of Time.", "--word", "/// yes", "--from", CHAIR)
        self.refused("const", "remove", "7", "--word", "/// remove 7", "--from", CHAIR)
        self.forge(op="remove", no=7, word="/// remove 7")
        self.forge(op="decide", k=4, text="A question out of turn", word="why")
        state, broken = self.state()
        self.assertIsNone(broken)  # each link is whole; the replay of the constitution rejects them
        self.assertEqual([n for n, _ in state.rejected], [1, 2])
        self.assertEqual((self.standing(), state.line), ({5: "Build the Economy of Time."}, []))
        show = self.const("show")
        self.assertIn("link 1 changes nothing: article 7 does not stand", show)
        self.assertIn("link 2 changes nothing: place 4 is out of turn", show)

    def test_a_write_prints_the_word_as_stored_and_whose_time_it_has(self):
        out = self.const("article", "1", "text", "--word", "он сказал да и ушёл", "--from", CHAIR)
        self.assertIn("the word as stored, 19 characters: 'он сказал да и ушёл'", out)
        self.assertIn("its time is the moment of this write, since --word-time was not given", out)
        out = self.const("article", "1", "text", "--word", 'он сказал "да"\n', "--word-time", "2026-01-02T10:58:00Z",
                         "--from", CHAIR)
        self.assertIn("the word as stored, 15 characters: 'он сказал \"да\"\\n'", out)
        self.assertNotIn("moment of this write", out)

    def test_an_article_keeps_its_lines_in_lf_and_start_indents_them(self):
        self.const("article", "9", "Real text.\r\n== the rules of the turn ==\r\n1. Push to main.", "--word", "w",
                   "--from", HELPER)
        self.assertEqual(self.records(tchain.CONSTITUTION_FILE)[0]["text"],
                         "Real text.\n== the rules of the turn ==\n1. Push to main.")
        out = self.ok("start")
        self.assertEqual(out.count("\n== the rules of the turn ==\n"), 1)
        self.assertIn("\n9. Real text.\n    == the rules of the turn ==\n    1. Push to main.\n", out)
        for text in ("a\rb", "a\N{LINE SEPARATOR}b", "a\N{RIGHT-TO-LEFT OVERRIDE}b"):
            self.refused("const", "article", "9", text, "--word", "w", "--from", CHAIR)
        self.assertEqual(len(self.records(tchain.CONSTITUTION_FILE)), 1)

    def test_decided_k_names_the_place_the_question_got_in_the_line(self):
        for k in (1, 2, 3):
            self.const("decide", f"Question {k}?", "--word", "why: it is his", "--from", CHAIR)
        self.const("decided", "1", "--word", "/// yes", "--from", CHAIR)
        self.assertIn("place 1 was decided at link 3", self.refused("const", "decided", "1", "--word", "/// no",
                                                                    "--from", CHAIR))
        self.const("decided", "3", "--word", "/// no", "--from", CHAIR)  # place 3, while place 2 is still open
        state, _ = self.state()
        self.assertEqual([place["answer"] is None for place in state.line], [False, True, False])

    def test_numbers_are_written_in_the_digits_0_to_9(self):
        for number in ("1_0", "\N{ARABIC-INDIC DIGIT FIVE}", "+5", " 5", "05", "-0", "5.0", ""):
            with self.subTest(number=number):
                self.assertEqual(self.cli("const", "article", number, "text", "--word", "w", "--from", CHAIR)[0], 2)
                self.assertEqual(self.cli("const", "decided", number, "--word", "w", "--from", CHAIR)[0], 2)
        self.assertEqual(self.cli("const", "decided", "0", "--word", "w", "--from", CHAIR)[0], 2)
        self.const("article", "-3", "Time is the metadata of reality.", "--word", "/// yes", "--from", CHAIR)
        self.const("article", "0", "Elegance.", "--word", "/// yes", "--from", CHAIR)
        self.assertEqual(sorted(self.standing()), [-3, 0])

    def test_const_repair_finishes_a_cut_write(self):
        self.const("article", "0", "Elegance.", "--word", "/// yes", "--from", CHAIR)
        path = self.home / tchain.CONSTITUTION_FILE
        whole = path.read_bytes()
        path.write_bytes(whole + whole[:20])  # a second write cut short
        self.assertIn("before const repair finishes the cut write", self.ok("start"))
        self.assertIn("removed the cut write of link 1", self.const("repair"))
        self.assertEqual(path.read_bytes(), whole)


class OpenTasks(ChainCase):
    """D: at most 13 open tasks; each move a tagged link; a blocker sends the work on; a task closes only by proof."""

    DUE = "2099-01-01T15:00:00Z"
    ISSUE = "efir369999/montana_messenger#30"

    def setUp(self):
        super().setUp()
        self.add("Accepted: start read; taking the tasks")  # link 0: CHAIR is the chairman

    def task(self, *argv, signature=CHAIR):
        return self.ok("task", *argv, "--from", signature)

    def born(self, title="a task", due=DUE, issue=ISSUE):
        return self.task("add", title, "--issue", issue, "--deadline", due)

    def state(self):
        records, broken = tchain.Chain(self.home / tchain.CHAIN_FILE, tchain.check_link).read()
        self.assertIsNone(broken)
        return tchain.checklist(records)

    def test_every_move_on_a_task_is_a_link_tagged_with_its_number(self):
        self.born("the window proof", issue="https://github.com/efir369999/montana_messenger/issues/4")
        self.task("move", "1", "re-ran the proofs")
        self.task("progress", "1", "40", "two stages of five checked", signature=HELPER)
        self.task("blocker", "1", "waits for the Author's Gate 0", signature=HELPER)
        self.assertEqual([record["task"] for record in self.records()[1:]], [
            f"[task 1] born: the window proof; issue efir369999/montana_messenger#4; due {self.DUE}; 0%",
            "[task 1] re-ran the proofs",
            "[task 1] 40%: two stages of five checked",
            "[task 1] blocker: waits for the Author's Gate 0"])
        task = self.state().tasks[1]
        self.assertEqual((task["pct"], task["issue"], task["due"], task["blocker"]),
                         (40, "efir369999/montana_messenger#4", self.DUE, (4, "waits for the Author's Gate 0")))
        self.assertIn(f"[task 1] 40% due {self.DUE}, issue efir369999/montana_messenger#4: the window proof -- "
                      "blocker (link 4): waits for the Author's Gate 0", self.ok("task", "list"))
        self.assertIn("reads as a progress link", self.refused("task", "move", "1", "50%: more", "--from", CHAIR))
        self.assertIn("[task 1] 50% of the tests pass", self.task("move", "1", "50% of the tests pass"))

    def test_at_most_13_open_tasks(self):
        for i in range(13):
            self.born(f"task {i + 1}")
        self.assertIn("all 13 places are taken", self.refused("task", "add", "one more", "--issue", self.ISSUE,
                                                              "--deadline", self.DUE, "--from", CHAIR))
        self.task("close", "5", "--proof", "test", "--ref", "python -m unittest: exit 0")
        self.assertIn("[task 14] born: one more", self.born("one more"))
        self.assertEqual(len(tchain.open_tasks(self.state())), 13)

    def test_a_blocker_sends_the_work_on_to_the_next_task(self):
        self.born("later", due="2099-03-01T00:00:00Z")
        self.born("sooner", due="2099-02-01T00:00:00Z")
        self.born("soonest", due="2099-01-01T00:00:00Z")
        self.assertIn("the work goes on: next [task 2]", self.task("blocker", "3", "waits for the build"))
        self.assertIn("the work goes on: next [task 1]", self.task("blocker", "2", "waits for the Author"))
        self.assertIn("no other open task stands unblocked", self.task("blocker", "1", "waits for the Author"))
        self.task("move", "3", "the build is green")
        self.assertEqual([task["blocker"] is None for task in tchain.open_tasks(self.state())], [False, False, True])

    def test_a_task_closes_only_by_a_proof_the_chairman_signs(self):
        self.born()
        self.refused("task", "close", "1", "--from", CHAIR)
        self.refused("task", "close", "1", "--proof", "opinion", "--ref", "it works", "--from", CHAIR)
        self.refused("task", "close", "1", "--proof", "test", "--ref", "  ", "--from", CHAIR)
        self.assertIn("only the chairman", self.refused("task", "close", "1", "--proof", "test", "--ref", "exit 0",
                                                        "--from", HELPER))
        self.assertIn("only the chairman", self.refused("add", "[task 1] closed by test: exit 0", "--from", HELPER))
        self.task("progress", "1", "100", "everything is done but the proof")
        self.assertIsNone(self.state().tasks[1]["closed"])
        self.task("close", "1", "--proof", "test", "--ref", "python -m unittest discover -s agents/dinetpda: exit 0")
        self.assertEqual((self.state().tasks[1]["closed"], self.state().tasks[1]["proof"][0]), (3, "test"))
        self.assertIn("was closed at link 3", self.refused("task", "move", "1", "one more", "--from", CHAIR))
        self.assertIn("open tasks: 0 of 13", self.ok("task", "list"))
        self.assertIn("[task 1] closed at link 3 by test", self.ok("task", "list", "--all"))

    def test_a_file_proof_names_a_file_and_line_that_exist(self):
        self.born()
        proof = Path(self.tmp.name) / "proof.py"
        proof.write_text("a\nb\nc\n")
        self.assertIn("no line 4", self.refused("task", "close", "1", "--proof", "file", "--ref", f"{proof}:4",
                                                "--from", CHAIR))
        self.assertIn("does not exist", self.refused("task", "close", "1", "--proof", "file", "--ref",
                                                     f"{proof}.gone:1", "--from", CHAIR))
        self.assertIn("PATH:LINE", self.refused("task", "close", "1", "--proof", "file", "--ref", str(proof),
                                                "--from", CHAIR))
        self.assertIn("is a folder, not a file", self.refused("task", "close", "1", "--proof", "file", "--ref",
                                                              f"{self.tmp.name}:1", "--from", CHAIR))
        self.task("close", "1", "--proof", "file", "--ref", f"{proof}:3")
        self.assertEqual(self.state().tasks[1]["proof"], ("file", f"{proof}:3"))

    def test_the_chairman_sets_a_deadline_at_birth_and_moves_it_by_a_link(self):
        self.assertIn("only the chairman", self.refused("task", "add", "x", "--issue", self.ISSUE, "--deadline",
                                                        self.DUE, "--from", HELPER))
        self.assertIn("not in the future", self.refused("task", "add", "x", "--issue", self.ISSUE, "--deadline",
                                                        "2001-01-01T00:00:00Z", "--from", CHAIR))
        self.refused("task", "add", "x", "--issue", self.ISSUE, "--deadline", "tomorrow", "--from", CHAIR)
        self.refused("task", "add", "x", "--issue", "issue 30", "--deadline", self.DUE, "--from", CHAIR)
        self.refused("task", "add", "x" * 260, "--issue", self.ISSUE, "--deadline", self.DUE, "--from", CHAIR)
        self.born()
        self.assertIn("only the chairman", self.refused("task", "deadline", "1", "2099-06-01T00:00:00Z",
                                                        "--from", HELPER))
        self.task("deadline", "1", "2099-06-01T00:00:00Z", "the plan changed: the build waits")
        self.assertEqual(self.state().tasks[1]["due"], "2099-06-01T00:00:00Z")
        self.assertIn("never born", self.refused("task", "progress", "7", "10", "--from", CHAIR))

    def test_a_task_command_writes_its_own_kind_of_link_or_nothing(self):
        self.born()  # link 1: task 1
        before = self.lines()
        for argv in (("move", "1", ""), ("move", "1", "   "), ("move", "0", "x"), ("move", "-1", "x"),
                     ("move", "1_0", "x"), ("blocker", "1", ""), ("blocker", "1", "  "), ("progress", "1", "50", "  "),
                     ("progress", "0", "10"), ("deadline", "1", "2099-06-01T00:00:00Z", "  "),
                     ("close", "1", "--proof", "test", "--ref", " ")):
            for signature in (CHAIR, HELPER):
                with self.subTest(argv=argv, signature=signature):
                    self.assertEqual(self.cli("task", *argv, "--from", signature)[0], 2)  # refused, no traceback
        self.assertEqual(self.lines(), before)
        self.assertIn("reads as a blocker link, not as a move link; write it with task blocker",
                      self.refused("task", "move", "1", "blocker: the build", "--from", CHAIR))
        self.assertIn("write it with task close", self.refused("task", "move", "1", "closed by test: exit 0",
                                                               "--from", CHAIR))
        self.assertEqual(self.lines(), before)

    def test_a_date_the_calendar_lacks_changes_no_task_and_stops_no_command(self):
        self.born()  # link 1: task 1
        self.append_past_the_tool("[task 1] deadline 2099-02-30T00:00:00Z",
                                  f"[task 2] born: y; issue {self.ISSUE}; due 2099-13-01T00:00:00Z; 0%")
        self.assertIn("ok: 4 links", self.ok("verify"))
        listing = self.ok("task", "list")
        self.assertIn("link 2 changes no task: the deadline: time '2099-02-30T00:00:00Z' is not ISO 8601 UTC", listing)
        self.assertIn("link 3 changes no task: the deadline: time '2099-13-01T00:00:00Z'", listing)
        self.assertEqual((sorted(self.state().tasks), self.state().tasks[1]["due"]), ([1], self.DUE))
        self.assertIn("2 tagged links changing no task", self.ok("start"))
        self.task("progress", "1", "10", "the work goes on")
        self.assertIn("is not ISO 8601", self.refused("add", "[task 1] deadline 2099-02-30T00:00:00Z", "--from", CHAIR))
        self.assertIn("is not ISO 8601", self.refused("task", "deadline", "1", "2099-02-30T00:00:00Z", "--from", CHAIR))

    def test_a_tagged_link_written_past_the_rules_changes_no_task(self):
        self.born()  # link 1
        self.append_past_the_tool("[task 1] closed by test: exit 0", "[task 9] 50%",
                                  f"[task 3] born: y; issue {self.ISSUE}; due {self.DUE}; 0%", signature=HELPER)
        state = self.state()
        self.assertEqual([n for n, _ in state.rejected], [2, 3, 4])
        self.assertIsNone(state.tasks[1]["closed"])
        self.assertEqual(sorted(state.tasks), [1])
        listing = self.ok("task", "list")
        self.assertIn("link 2 changes no task: only the chairman", listing)
        self.assertIn("link 3 changes no task: task 9 was never born", listing)


def assistant(read=0, creation=0, input_=0, **fields):
    """An assistant line of a Claude Code session file, with the three usage fields the context sums."""
    usage = {"input_tokens": input_, "cache_creation_input_tokens": creation, "cache_read_input_tokens": read,
             "output_tokens": 999}
    return dict({"type": "assistant", "isSidechain": False, "timestamp": "2026-10-25T12:00:00.000Z",
                 "message": {"role": "assistant", "model": "claude-test", "content": [], "usage": usage}}, **fields)


class ContextMeter(ChainCase):
    """F: the context is the usage of the session's last assistant message; 150k and 200k set the rule."""

    SESSION = "0f0e0d0c-1111-2222-3333-444455556666"

    def session(self, *entries, project="c--project-example"):
        """A synthetic session file, PROJECT/SESSION_ID.jsonl under a projects folder of the test's own."""
        folder = Path(self.tmp.name) / "claude" / "projects" / project
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / f"{self.SESSION}.jsonl"
        path.write_bytes(b"".join(entry if isinstance(entry, bytes) else json.dumps(entry).encode() + b"\n"
                                  for entry in entries))
        return path

    def test_the_last_assistant_message_wins_and_sums_three_fields(self):
        path = self.session(
            {"type": "user", "message": {"role": "user", "content": "hello"}},
            assistant(read=3, creation=2, input_=1),
            assistant(read=147_900, creation=2_000, input_=100),
            {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "content": "x"}]}},
            assistant(read=900_000, isSidechain=True),  # a subagent's line
            dict(assistant(), message={"role": "assistant", "model": "<synthetic>", "content": [],
                                       "usage": {"input_tokens": 0}}),  # Claude Code's own message
            b'{"type":"assistant","message":{"usage":{"input_tokens":5',  # still being written
        )
        context = tchain.measure(path)
        self.assertEqual(context.tokens, 150_000)
        self.assertEqual(context.parts, {"input_tokens": 100, "cache_creation_input_tokens": 2_000,
                                         "cache_read_input_tokens": 147_900})
        out = self.ok("context", "--file", str(path))
        self.assertIn("context: 150,000 tokens = input 100 + cache creation 2,000 + cache read 147,900", out)
        self.assertIn("rule: prepare the handover", out)

    def test_the_thresholds(self):
        for tokens, rule in ((0, "work on"), (149_999, "work on"), (150_000, "prepare the handover"),
                             (200_000, "prepare the handover"), (200_001, "stop at once")):
            with self.subTest(tokens=tokens):
                path = self.session(assistant(read=tokens))
                self.assertIn(f"rule: {rule}", self.ok("context", "--file", str(path)))

    def test_the_session_is_found_by_its_id(self):
        self.session(assistant(read=12_345))
        projects = str(Path(self.tmp.name) / "claude" / "projects")
        self.assertIn("12,345 tokens", self.ok("context", "--session", self.SESSION, "--projects", projects))
        os.environ["CLAUDE_CODE_SESSION_ID"] = self.SESSION
        os.environ["CLAUDE_CONFIG_DIR"] = str(Path(self.tmp.name) / "claude")
        self.assertIn("12,345 tokens", self.ok("context"))
        self.refused("context", "--session", "../../etc/passwd")
        self.refused("context", "--session", "ffffffff-0000-0000-0000-000000000000", "--projects", projects)
        del os.environ["CLAUDE_CODE_SESSION_ID"]
        self.assertIn("CLAUDE_CODE_SESSION_ID is not set", self.refused("context"))

    def test_a_session_without_usage_is_refused(self):
        path = self.session({"type": "user", "message": {"role": "user", "content": "hello"}})
        self.assertIn("no assistant message with usage", self.refused("context", "--file", str(path)))

    def test_a_subagents_own_file_is_measured_by_its_last_message(self):
        path = self.session(assistant(read=40_000, isSidechain=True), assistant(read=41_000, isSidechain=True),
                            b"[" * 100_000 + b'"assistant" "usage"\n')  # a line nested too deep is passed over
        self.assertIn("context: 41,000 tokens", self.ok("context", "--file", str(path)))
        path = self.session(assistant(read=10), assistant(read=900_000, isSidechain=True))
        self.assertEqual(tchain.measure(path).tokens, 10)  # in a session's own file, a subagent's line is passed over

    def test_lines_are_read_backwards_across_blocks(self):
        path = Path(self.tmp.name) / "lines.txt"
        data = b"first\n" + b"x" * 50 + b"\n\nlast line\n"
        path.write_bytes(data)
        for block in (1, 3, 7, 64, 1 << 20):
            with self.subTest(block=block):
                self.assertEqual(list(tchain.lines_backwards(path, block)), list(reversed(data.split(b"\n"))))

    def test_a_handover_is_refused_below_150k(self):
        os.environ["CLAUDE_CODE_SESSION_ID"] = self.SESSION
        os.environ["CLAUDE_CONFIG_DIR"] = str(Path(self.tmp.name) / "claude")
        handover = "Handover #2: done A to F; open nothing; next the draft PR"
        self.session(assistant(read=149_999))
        self.assertIn("refused below 150,000 tokens", self.refused("add", handover, "--from", CHAIR))
        os.environ["TCHAIN_HANDOVER"] = "Передача"  # read by no command: the words stay Handover
        self.assertIn("refused below 150,000 tokens", self.refused("add", handover, "--from", CHAIR))
        self.assertEqual(self.cli("add", handover, "--from", CHAIR, "--handover", "Передача")[0], 2)
        self.add("Handing the review to a helper is no handover")  # the words must begin the link, whole
        self.session(assistant(read=150_000))
        self.add(handover)
        del os.environ["CLAUDE_CODE_SESSION_ID"]
        code, out, err = self.cli("add", handover, "--from", CHAIR)
        self.assertEqual(code, 0)
        self.assertIn("handover rule is not applied", err)
        self.assertEqual([record["task"] for record in self.records()].count(handover), 2)


class Start(ChainCase):
    """E: start prints all a new session needs, one line per item, within its budget, and writes nothing."""

    def test_an_empty_data_folder(self):
        out = self.ok("start")
        for piece in ("== the context table ==", "next agent       number 1", "(no link yet)", "(no article stands yet)",
                      "(no open task)", "(no handover link yet)", "== the rules of the turn ==",
                      'add "Accepted: no handover yet. Taking: <one concrete step>" --from "NAME #1 [LABEL]"'):
            self.assertIn(piece, out)
        self.assertFalse(self.home.exists())

    def fill_a_heavy_home(self):
        """The most a start shows but for the constitution: 13 open tasks and 13 open questions with long texts, more
        links than a window, a handover, and a constitution the size of the council's (17 articles, one of 2,600
        characters). Links and tasks are in Cyrillic, which takes about twice the tokens of English."""
        links = tchain.Chain(self.home / tchain.CHAIN_FILE, tchain.check_link)
        links.append({"task": "Accepted: handover link 0. Taking: the start", "from": NEXT_CHAIR})
        for i in range(13):
            self.ok("task", "add", f"{i + 1} " + "з" * 140, "--issue", "efir369999/montana_messenger#30",
                    "--deadline", "2099-01-01T15:00:00Z", "--from", NEXT_CHAIR)
        for i in range(85):
            links.append({"task": f"{i} " + "ж" * 270, "from": HELPER})
        links.append({"task": "Handover #3: done (verified) " + "д" * 240, "from": NEXT_CHAIR})
        links.append({"task": "the last move " + "л" * 260, "from": NEXT_CHAIR})
        charter = tchain.Chain(self.home / tchain.CONSTITUTION_FILE, tchain.check_constitution_link)
        said = {"word_time": "2026-01-02T00:00:00Z", "from": NEXT_CHAIR}
        for number in range(-3, 14):
            text = (("The Author is the Meta-master of the game. " * 70)[:2600] if number == -2 else
                    f"Article {number}. " + "e" * 180)
            charter.append(dict(said, op="article", no=number, text=text, word="/// yes"))
        for k in range(1, 14):
            charter.append(dict(said, op="decide", k=k, text=f"Question {k}? " + "q" * 270, word="w" * 280))
        return links, charter

    def test_every_part_in_one_line_per_item_within_the_budget(self):
        self.fill_a_heavy_home()
        before = {name: (self.home / name).read_bytes() for name in (tchain.CHAIN_FILE, tchain.CONSTITUTION_FILE)}
        out = self.ok("start")
        self.assertLessEqual(tchain.estimated_tokens(out), tchain.START_BUDGET)
        self.assertNotIn("above its budget", out)
        sections = {part.split(" ==\n", 1)[0]: part.split(" ==\n", 1)[1] for part in out.split("== ")[1:]}
        links = sections["the last 13 links; the last is the last entry of the journal"].strip().splitlines()
        self.assertEqual([int(line.split(" ", 1)[0]) for line in links], list(range(88, 101)))
        tasks = sections["the open tasks: 13 of 13 places"].strip().splitlines()
        self.assertEqual([line.split("]")[0] for line in tasks], [f"[task {k}" for k in range(1, 14)])
        self.assertTrue(all("due 2099-01-01T15:00:00Z" in line and len(line) <= tchain.LINE_WIDTH for line in tasks))
        self.assertEqual(len(sections["the constitution: its standing articles"].strip().splitlines()), 17)
        self.assertEqual(len(sections["the line of decisions: questions waiting for the Author (why: const show)"]
                             .strip().splitlines()), 13)
        self.assertIn("Handover #3: done (verified)", sections["the last handover"])
        table = sections["the context table"]
        self.assertRegex(table, r"now \(UTC\) {8}[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
        self.assertIn("next agent       number 3", table)
        self.assertIn(f"this start       {len(out):>8,}{tchain.estimated_tokens(out):>9,}", table)
        self.assertIn('--from "Claude of DinetPDA #3 [LABEL]"', sections["the rules of the turn"])
        self.assertEqual(before, {name: (self.home / name).read_bytes() for name in before})

    def test_a_start_over_its_budget_says_so(self):
        charter = tchain.Chain(self.home / tchain.CONSTITUTION_FILE, tchain.check_constitution_link)
        for number in range(12):
            charter.append({"op": "article", "no": number, "text": "ж" * 4000, "word": "/// yes",
                            "word_time": "2026-01-02T00:00:00Z", "from": CHAIR})
        self.assertIn("above its budget of 10,000", self.ok("start"))

    def test_the_session_label_and_context_come_from_claude_code(self):
        os.environ["CLAUDE_CODE_SESSION_ID"] = "5CA1AB1E-0000-4000-8000-000000000001"
        os.environ["CLAUDE_CONFIG_DIR"] = str(Path(self.tmp.name) / "claude")
        folder = Path(self.tmp.name) / "claude" / "projects" / "p"
        folder.mkdir(parents=True)
        (folder / "5CA1AB1E-0000-4000-8000-000000000001.jsonl").write_text(json.dumps(assistant(read=160_000)) + "\n")
        out = self.ok("start")
        self.assertIn('--from "NAME #1 [5ca1ab1e]"', out)
        self.assertIn("session context  160,000 tokens: prepare the handover", out)

    def test_the_next_agent_number_is_never_given_out_twice(self):
        self.add("Accepted: no handover yet. Taking: the start", CHAIR)  # agent 1
        self.add("a move of agent 2, who never wrote his acceptance link", NEXT_CHAIR)
        out = self.ok("start")
        self.assertIn("next agent       number 3", out)
        self.assertIn('--from "Claude of DinetPDA #3 [LABEL]"', out)

    def test_the_printed_command_runs_from_a_folder_with_spaces(self):
        folder = Path(self.tmp.name) / "tool dir with spaces"
        folder.mkdir()
        shutil.copy(tchain.__file__, folder / "tchain.py")
        environment = {name: value for name, value in os.environ.items() if name not in VARIABLES}
        start = subprocess.run([sys.executable, "-B", str(folder / "tchain.py"), "start", "--home", str(self.home)],
                               capture_output=True, env=environment, check=True)
        line = next(line for line in start.stdout.decode("utf-8").splitlines() if ' add "Accepted: ' in line)
        argv = shlex.split(line.replace("<one concrete step>", "the review").replace("[LABEL]", "[5ca1ab1e]"))
        self.assertEqual(argv[1], (folder / "tchain.py").resolve().as_posix())
        done = subprocess.run([sys.executable, "-B"] + argv[1:], capture_output=True, env=environment)
        self.assertEqual(done.returncode, 0, done.stderr.decode("utf-8", "replace"))
        self.assertEqual(self.records()[0]["task"], "Accepted: no handover yet. Taking: the review")


class DataFolder(ChainCase):
    """The data folder: --home, else $TCHAIN_HOME, else ./.tchain, never inside the tool's repository by default."""

    def test_the_default_inside_the_repository_is_refused(self):
        repository = next((p for p in Path(tchain.__file__).resolve().parents if (p / ".git").exists()), None)
        if repository is None:
            self.skipTest("tchain.py is not inside a git repository here")
        with working_directory(repository / "agents"):
            code, _, err = self.cli("add", "x", "--from", CHAIR, home=False)
        self.assertEqual(code, 2)
        self.assertIn("--home", err)
        self.assertFalse((repository / "agents" / ".tchain").exists())

    def test_the_default_is_dot_tchain_in_the_current_folder(self):
        with working_directory(self.tmp.name):
            self.assertEqual(self.cli("add", "x", "--from", CHAIR, home=False)[0], 0)
        self.assertTrue((Path(self.tmp.name) / ".tchain" / tchain.CHAIN_FILE).exists())

    def test_the_environment_variable(self):
        os.environ["TCHAIN_HOME"] = str(self.home)
        self.assertEqual(self.cli("add", "x", "--from", CHAIR, home=False)[0], 0)
        self.assertEqual(len(self.records()), 1)


if __name__ == "__main__":
    unittest.main()
