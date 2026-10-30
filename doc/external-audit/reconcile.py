#!/usr/bin/env python3
"""Compare the Canon version, AIR identifiers, parameter digest and Genesis wherever a committed
document states them; exit 0 only when each quantity has one current value.

A value is historical, and left out of the comparison, when the line it starts on carries the
word "historical" (in any case).
"""
import argparse
from pathlib import Path
import re
import subprocess

SPEC = ('core/docs/', 'Audit/Protocol-13/source/docs/')
CODE = ('core/Montana-Core/', 'Audit/Protocol-13/source/Montana-Core/')
VERSIONS = tuple(folder + 'VERSION.md' for folder in CODE)
PROSE = ('README.md', 'core/README.md', 'Audit/README.md')
PROSE_DIR = 'Audit/Protocol-13/'
REQUIRED = ('canon_version', 'air_hash', 'published_parameters', 'genesis_state_hash')
HISTORICAL = re.compile(r'\bhistorical\b', re.I)

HEX = r'([0-9a-fA-F]{64})\b'
BYTES = r'\[\s*((?:0x[0-9a-fA-F]{2}\s*,\s*){31}0x[0-9a-fA-F]{2})\s*,?\s*\]'
NAMES = r'(air_hash|genesis_state_hash|published_parameters)'


def named(match):
    return match.group(1)


def described(match):
    return 'air identifier of the ' + match.group(1)


# (kind of document, pattern whose last group is the value, quantity or how to read it)
TEXT = (
    ('canon', re.compile(r'^\*\*Version:\*\*\s*(\d+\.\d+\.\d+)', re.M), 'canon_version'),
    ('md', re.compile(r'^\|\s*Canon\b[^\n]*\|\s*(\d+\.\d+\.\d+)\s*\|\s*$', re.M), 'canon_version'),
    ('prose', re.compile(r'\bCanon (\d+\.\d+\.\d+)\b'), 'canon_version'),
    ('any', re.compile(r'\bidentifier of the (\w+)\s*=\s*' + HEX), described),
    ('any', re.compile(r'^\|\s*`air_hash`[^\n]*\|\s*' + HEX + r'\s*\|', re.M), 'air_hash'),
    ('any', re.compile(r'\b' + NAMES + r'`?\s*(?:=|:|\bis\b)\s*`?' + HEX), named),
    ('any', re.compile(r'\b' + NAMES + r'\s*=\s*SHA-256\([^=]{0,400}?=\s*' + HEX), named),
    ('any', re.compile(r'\bGenesis\b[^`|]{0,60}?`?' + HEX), 'genesis_state_hash'),
    ('any', re.compile(r'\bparameters?\s+digest\b[^`|]{0,60}?`?' + HEX), 'published_parameters'),
    ('rs', re.compile(r'"' + NAMES + r'"\s*,\s*' + BYTES), named),
)


def git(root, *args, data=None):
    result = subprocess.run(['git', '-C', str(root), *args], input=data, capture_output=True)
    if result.returncode:
        raise ValueError('git could not read the requested committed object')
    return result.stdout


def kinds(path):
    """Which patterns apply to a committed path, or None when it is outside the comparison."""
    if path.endswith('.rs') and path.startswith(CODE):
        return {'any', 'rs'}
    if path in VERSIONS:
        return {'any', 'md'}
    if path.endswith('.md') and path.startswith(SPEC):
        return {'any', 'md', 'canon' if path.endswith('/Montana Canon.md') else 'prose'}
    if path in PROSE or (path.startswith(PROSE_DIR) and path.endswith('.md')
                         and '/' not in path[len(PROSE_DIR):]):
        return {'any', 'md', 'prose'}
    return None


def statements(path, text, applies):
    """Every (quantity, value, path, line, historical) the text states, in order of position."""
    found = {}
    lines = text.split('\n')
    for kind, pattern, quantity in TEXT:
        if kind not in applies:
            continue
        for match in pattern.finditer(text):
            value = match.group(match.lastindex).lower()
            key = quantity if isinstance(quantity, str) else quantity(match)
            if value.startswith('0x'):
                value = ''.join(b[2:].lower() for b in re.findall(r'0x[0-9a-fA-F]{2}', value))
            line = text.count('\n', 0, match.start(match.lastindex)) + 1
            historical = bool(HISTORICAL.search(lines[line - 1]))
            # Equal claims may overlap patterns, but a different value must survive.
            found[(line, key, value)] = (key, value, path, line, historical)
    return [found[k] for k in sorted(found)]


def collect(root, revision):
    commit = git(root, 'rev-parse', '--verify', '--end-of-options',
                 revision + '^{commit}').decode().strip()
    entries = []
    for record in git(root, 'ls-tree', '-r', '-z', commit).split(b'\0'):
        if not record:
            continue
        meta, path = record.decode('utf-8').split('\t', 1)
        _, kind, oid = meta.split()
        applies = kinds(path)
        if kind == 'blob' and applies:
            entries.append((path, oid, applies))
    if not entries:
        return commit, []
    batch = git(root, 'cat-file', '--batch', data=''.join(oid + '\n' for _, oid, _ in entries).encode())
    result, offset = [], 0
    for path, oid, applies in entries:
        header_end = batch.index(b'\n', offset)
        size = int(batch[offset:header_end].split()[2])
        body = batch[header_end + 1:header_end + 1 + size]
        offset = header_end + 2 + size
        result.extend(statements(path, body.decode('utf-8'), applies))
    return commit, result


def disagreements(found):
    """The quantities whose current values differ, and the required ones nobody states."""
    current = {}
    for key, value, path, line, historical in found:
        if not historical:
            current.setdefault(key, {}).setdefault(value, []).append(f'{path}:{line}')
    problems = [(key, values) for key, values in sorted(current.items()) if len(values) > 1]
    missing = [key for key in REQUIRED if key not in current]
    return problems, missing


def report(root, revision):
    commit, found = collect(root, revision)
    out = [f'reconcile: commit {commit}', '', 'quantity | value | where | standing',
           '---|---|---|---']
    for key, value, path, line, historical in sorted(found, key=lambda s: (s[0], s[2], s[3])):
        out.append(f'{key} | {value} | {path}:{line} | {"historical" if historical else "current"}')
    problems, missing = disagreements(found)
    out.append('')
    for key, values in problems:
        out.append(f'DISAGREE {key}: {len(values)} current values')
        for value, places in values.items():
            out.append(f'  {value} at ' + ', '.join(places))
    for key in missing:
        out.append(f'MISSING {key}: no document states a current value')
    if problems or missing:
        out.append(f'reconcile: {len(problems)} disagreeing, {len(missing)} missing')
        return 1, out
    out.append(f'reconcile: {len({s[0] for s in found})} quantities agree across {len(found)} statements')
    return 0, out


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--revision', default='HEAD', help='public Git revision to compare')
    args = parser.parse_args()
    try:
        code, out = report(args.repo, args.revision)
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(2, 'reconcile: ' + str(error) + '\n')
    print('\n'.join(out))
    raise SystemExit(code)


if __name__ == '__main__':
    main()
