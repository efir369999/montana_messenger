#!/usr/bin/env python3
"""Reads a copy's «groups.held» the way iOS 2235 decodes it: JSONDecoder over [String: MTGroupState]
(MontanaGroup.swift:17-93). Every non-optional field must be present with its type, an optional one may be absent but
never of another type; a key the struct does not know is skipped, as Swift's synthesized Decodable skips it.

usage: python -I tools/groups_copy_check.py <groups-held.json>   -> "decodes: N groups" or the first refusal
"""
import json
import sys


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def is_num(v):
    return (isinstance(v, (int, float))) and not isinstance(v, bool)


def member(v, where):
    if not isinstance(v, dict):
        raise ValueError(f"{where}: a member is not an object")
    for k in ("seat", "pipe"):
        if not isinstance(v.get(k), str):
            raise ValueError(f"{where}: member.{k} is not a string")


def act(v, where):
    if not isinstance(v, dict) or not isinstance(v.get("e"), str) or not is_num(v.get("at")):
        raise ValueError(f"{where}: an act needs e (string) and at (number)")
    if "p" in v and not (isinstance(v["p"], list) and all(isinstance(x, str) for x in v["p"])):
        raise ValueError(f"{where}: act.p is not a list of strings")
    if "t" in v and not isinstance(v["t"], str):
        raise ValueError(f"{where}: act.t is not a string")


def state(key, s):
    w = f"group {key}"
    if not isinstance(s, dict):
        raise ValueError(f"{w}: not an object")
    required = {"id": str, "title": str, "about": str, "owner": str, "me": str}
    for k, t in required.items():
        if not isinstance(s.get(k), t):
            raise ValueError(f"{w}: {k} missing or not a string")
    if s.get("kind") not in ("g", "c"):
        raise ValueError(f"{w}: kind is not «g» or «c» (MTGroupKind)")
    if not isinstance(s.get("members"), list):
        raise ValueError(f"{w}: members missing")
    for i, m in enumerate(s["members"]):
        member(m, f"{w} members[{i}]")
    if not is_int(s.get("count")):
        raise ValueError(f"{w}: count missing or not a whole number")
    if not isinstance(s.get("names"), dict) or not all(isinstance(v, str) for v in s["names"].values()):
        raise ValueError(f"{w}: names missing or not a map of strings")
    if not is_num(s.get("at")):
        raise ValueError(f"{w}: at missing or not a number")
    for k in ("left", "removed", "silent", "signs", "reacts"):
        if k in s and not isinstance(s[k], bool):
            raise ValueError(f"{w}: {k} is not a Bool")
    for k in ("invite", "faceTag", "face"):
        if k in s and not isinstance(s[k], str):
            raise ValueError(f"{w}: {k} is not a string")
    if "admins" in s and not (isinstance(s["admins"], list) and all(isinstance(x, str) for x in s["admins"])):
        raise ValueError(f"{w}: admins is not a list of strings")
    if "readBy" in s and not (isinstance(s["readBy"], dict) and all(is_int(v) for v in s["readBy"].values())):
        raise ValueError(f"{w}: readBy is not a map of whole numbers (Int64)")
    for i, m in enumerate(s.get("banned", [])):
        member(m, f"{w} banned[{i}]")
    for i, a in enumerate(s.get("acts", [])):
        act(a, f"{w} acts[{i}]")
    if s["id"] != key:
        raise ValueError(f"{w}: id «{s['id']}» is not its key")


def main():
    held = json.load(open(sys.argv[1], encoding="utf-8"))
    if not isinstance(held, dict):
        raise SystemExit("refused: the store is not [String: MTGroupState]")
    for k, s in held.items():
        state(k, s)
    kinds = sorted(s["kind"] for s in held.values())
    print(f"decodes: {len(held)} groups ({kinds.count('g')} groups, {kinds.count('c')} channels)")


if __name__ == "__main__":
    try:
        main()
    except ValueError as e:
        raise SystemExit(f"refused: {e}")
