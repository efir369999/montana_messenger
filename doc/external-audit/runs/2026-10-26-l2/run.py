#!/usr/bin/env python3
"""Pinned core checks; output lives outside the source; no production networking."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

PIN = 'a835c1c3ff4bc95ea3c75e02391d3d69e2e08833'
NS = ['unshare', '-n', '--', 'sh', '-c', 'ip link set lo up && exec "$@"', 'audit']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--jobs', type=int, default=4)
    args = parser.parse_args()
    root = args.directory.resolve()
    root.mkdir(parents=True, exist_ok=True)
    source = root / 'source'
    out = root / 'evidence'
    out.mkdir(exist_ok=True)
    if (out / 'results.json').exists():
        raise SystemExit('Refusing to overwrite a prior run; choose a fresh directory')
    rows = []
    env = os.environ.copy()
    env['PATH'] = '/root/.cargo/bin:/opt/ossl35/bin:' + env['PATH']
    env['LD_LIBRARY_PATH'] = '/opt/ossl35/lib64:/opt/ossl35/lib'
    env['RUSTUP_TOOLCHAIN'] = '1.92.0'
    env['RUST_BACKTRACE'] = '1'

    def run(name, command, cwd=source, isolated=False, timeout=3600, extra=None):
        command = (NS if isolated else []) + command
        run_env = env.copy()
        if extra:
            run_env.update(extra)
        start = time.time()
        with (out / (name + '.log')).open('w') as log:
            process = subprocess.Popen(command, cwd=cwd, env=run_env, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            timed_out = False
            try:
                rc = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                rc = 124
        row = {'name': name, 'command': command, 'cwd': str(cwd), 'exit': rc,
               'timed_out': timed_out, 'elapsed_seconds': round(time.time() - start, 3),
               'environment': extra or {},
               'log_sha256': hashlib.sha256((out / (name + '.log')).read_bytes()).hexdigest()}
        rows.append(row)
        (out / 'results.json').write_text(json.dumps(rows, indent=2))
        print(json.dumps(row), flush=True)
        return rc

    if not source.exists():
        source.mkdir()
        for name, command in [
            ('git-init', ['git', 'init']),
            ('git-remote', ['git', 'remote', 'add', 'origin',
                            'https://github.com/efir369999/montana_messenger.git']),
            ('git-fetch', ['git', 'fetch', '--depth=1', 'origin', PIN]),
            ('git-checkout', ['git', 'checkout', '--detach', PIN]),
        ]:
            if run(name, command, timeout=600):
                raise SystemExit(name)
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source,
                                     text=True).strip()
    if actual != PIN:
        raise SystemExit('Wrong source pin')
    run('rustc', ['rustc', '-Vv'], timeout=30)
    run('openssl', ['openssl', 'version', '-a'], timeout=30)
    run('python-tests', ['python3', '-m', 'unittest', 'discover', '-s',
                        'doc/external-audit/tests', '-v'], isolated=True, timeout=300)
    for name in ['snapshot', 'reconcile']:
        run(name, ['python3', 'doc/external-audit/' + name + '.py', '--revision', PIN],
            isolated=True, timeout=300)
    run('traffic-control', ['python3', 'doc/external-audit/traffic.py', '--demo'],
        isolated=True, timeout=60)
    probe = ['--manifest-path', 'doc/external-audit/probes/Cargo.toml']
    target = {'CARGO_TARGET_DIR': str(root / 'target-probes')}
    if not run('probe-fetch', ['cargo', 'fetch', '--locked'] + probe, extra=target):
        run('probes', ['cargo', 'test', '--release', '--locked', '--offline',
                      '--jobs', str(args.jobs)] + probe, isolated=True, extra=target)

    for label in ['Montana-Core', 'Code']:
        workspace = source / 'core' / label
        target = {'CARGO_TARGET_DIR': str(root / ('target-' + label))}
        run(label + '-fmt', ['cargo', 'fmt', '--all', '--check'], workspace,
            isolated=True, timeout=120, extra=target)
        if run(label + '-fetch', ['cargo', 'fetch', '--locked'], workspace, extra=target):
            continue
        run(label + '-clippy', ['cargo', 'clippy', '--workspace', '--all-targets',
                               '--locked', '--offline', '--jobs', str(args.jobs),
                               '--', '-D', 'warnings'], workspace, isolated=True, extra=target)
        built = run(label + '-test-build', ['cargo', 'test', '--workspace', '--release',
                    '--locked', '--offline', '--jobs', str(args.jobs), '--no-run',
                    '--message-format=json'], workspace, isolated=True, extra=target)
        if built == 0:
            metadata = subprocess.check_output(['cargo', 'metadata', '--offline', '--locked',
                '--format-version=1', '--no-deps'], cwd=workspace, env={**env, **target}, text=True)
            packages = {p['id']: p for p in json.loads(metadata)['packages']}
            artifacts = {}
            for line in (out / (label + '-test-build.log')).read_text().splitlines():
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if (item.get('reason') == 'compiler-artifact' and item.get('executable')
                        and item.get('profile', {}).get('test')):
                    artifacts[item['executable']] = item
            (out / (label + '-targets.json')).write_text(json.dumps(list(artifacts.values()), indent=2))
            for index, (executable, item) in enumerate(sorted(artifacts.items())):
                package = packages[item['package_id']]
                directory = Path(package['manifest_path']).parent
                name = f"{label}-test-{index:03}-{item['target']['name']}"
                run(name, [executable, '--test-threads=1'], directory, isolated=True,
                    extra={**target, 'CARGO_MANIFEST_DIR': str(directory),
                           'CARGO_PKG_NAME': package['name']})
        run(label + '-doctests', ['cargo', 'test', '--workspace', '--doc', '--release',
            '--locked', '--offline', '--jobs', str(args.jobs)], workspace,
            isolated=True, extra=target)
        run(label + '-release', ['cargo', 'build', '--workspace', '--release', '--locked',
            '--offline', '--jobs', str(args.jobs)], workspace, isolated=True, extra=target)
    (out / 'finished.json').write_text(json.dumps({'pin': PIN, 'results': rows}, indent=2))


if __name__ == '__main__':
    main()
