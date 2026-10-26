#!/usr/bin/env python3
"""Repeat only the retained differential binary with an explicit existing liboqs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

PIN = 'a835c1c3ff4bc95ea3c75e02391d3d69e2e08833'
NAME = 'Montana-Core-test-028-differential'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('liboqs', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    root, library, output = args.root.resolve(), args.liboqs.resolve(), args.output.resolve()
    source = root / 'source'
    pin = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    if pin != PIN or not library.is_file():
        raise SystemExit('Source pin or library precondition failed')
    original = next(row for row in json.loads((root / 'evidence/results.json').read_text())
                    if row['name'] == NAME)
    original_log = root / 'evidence' / (NAME + '.log')
    if sha(original_log) != original['log_sha256'] or original['exit'] != 101:
        raise SystemExit('Original failure does not match the retained evidence')
    command = original['command'] + ['--nocapture']
    binary = Path(original['command'][-2])
    if binary.parent != root / 'target-Montana-Core/release/deps' or not binary.is_file():
        raise SystemExit('Unexpected differential executable')
    output.mkdir(exist_ok=False)
    (output / 'tmp').mkdir()
    env = os.environ.copy()
    env.update(PATH='/root/.cargo/bin:/opt/ossl35/bin:' + env['PATH'],
               LD_LIBRARY_PATH='/opt/ossl35/lib64:/opt/ossl35/lib',
               RUSTUP_TOOLCHAIN='1.92.0', RUST_BACKTRACE='1')
    env.update(original['environment'])
    env.update(MT_LIBOQS=str(library), TMPDIR=str(output / 'tmp'))
    row = {'source_pin': pin, 'original': original, 'command': command,
           'cwd': original['cwd'], 'binary_sha256': sha(binary),
           'library_path': str(library), 'library_sha256': sha(library),
           'environment': {key: env[key] for key in ('PATH', 'LD_LIBRARY_PATH',
                           'RUSTUP_TOOLCHAIN', 'RUST_BACKTRACE', 'CARGO_TARGET_DIR',
                           'CARGO_MANIFEST_DIR', 'CARGO_PKG_NAME', 'MT_LIBOQS', 'TMPDIR')},
           'as_of_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
           'main_runner_complete': False, 'timed_out': False}
    started = time.monotonic()
    with (output / 'tests.log').open('x') as log:
        try:
            result = subprocess.run(command, cwd=original['cwd'], env=env,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=60)
            row['exit'] = result.returncode
        except subprocess.TimeoutExpired:
            row.update(exit=124, timed_out=True)
    row['elapsed_seconds'] = round(time.monotonic() - started, 3)
    row['log_sha256'] = sha(output / 'tests.log')
    row['binary_sha256_after'] = sha(binary)
    row['library_sha256_after'] = sha(library)
    (output / 'results.json').write_text(json.dumps(row, indent=2) + '\n')
    print(json.dumps(row), flush=True)
    raise SystemExit(row['exit'])


if __name__ == '__main__':
    main()
