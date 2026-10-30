#!/usr/bin/env python3
"""Prepare the frameworks of Montana for the Mac (Catalyst) or the phone from public source, reproducibly."""
# REPRODUCIBLE BY ANY BUILDER (Constitution [I-14]: «every release build ... is reproducible byte for byte from publicly published
# source by any independent builder»; the author's words 21.10.2026 17:4x and 17:58 UTC: «there is no reproducible build of the
# applications -- fix it», «while you wait for OZ 1, close OZ 2»). Measured on the release 2274 (21.10.2026): its main binary held
# 1788 absolute paths of this Mac -- 1561 of the Go module cache and the tree xray was built in, 174 of the cargo registry and the
# core, 7 of OPENSSLDIR in a session tree -- and its core was built from a working folder with uncommitted changes. So:
#   * the core is the tree of one committed commit (git archive), never a working folder, and the commit is stamped in SOURCE;
#   * every path a compiler could write is rewritten to a fixed name under /montana (no file lives there on any machine);
#   * OpenSSL is configured with a fixed prefix and directory, installed under DESTDIR, its build date pinned to the epoch;
#   * the Xray engine is built here, -trimpath, by the Go toolchain and gomobile its go.mod names; WebRTC is the published binary
#     whose SHA-256 fetch-webrtc.sh pins. Nothing is taken from a framework folder some other road left behind.
# One road for both platforms (OZ 1, the phone after the Mac, 22.10.2026): the platform changes the Rust target, the SDK, the clang
# triple, OpenSSL's configuration and the slice checked; the phone adds the protocol core (mt-boundary of Montana-Core, the same
# committed commit) and the tunnel's stack (hev-socks5-tunnel at its pinned commit), which the Mac product does not carry.
import argparse
import io
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
FIXED = '/montana'
RUST = '1.92.0'
RUSTUP = shutil.which('rustup') or str(Path.home() / '.cargo/bin/rustup')
DEPLOYMENT = '17.2'
WORDS = 'Montana wordlist.txt'
CORE_LINE = 'publish/core-english'
# openssl-src has no Catalyst target by name («don't know how to configure OpenSSL for aarch64-apple-ios-macabi», 2273's Mac road):
# the Mac is configured as macOS arm64 with the Catalyst triple; the phone takes the configuration OpenSSL itself names for a 64-bit
# iPhone (ios-common: no shared objects, no async)
PLATFORMS = {
    'mac': {'target': 'aarch64-apple-ios-macabi', 'sdk': 'macosx', 'triple': 'arm64-apple-ios' + DEPLOYMENT + '-macabi',
            'openssl': 'darwin64-arm64-cc', 'xray': 'maccatalyst/arm64', 'variant': 'maccatalyst', 'slug': 'macabi',
            'carries': ['MontanaBindings', 'MontanaXray', 'WebRTC']},
    'phone': {'target': 'aarch64-apple-ios', 'sdk': 'iphoneos', 'triple': 'arm64-apple-ios' + DEPLOYMENT,
              'openssl': 'ios64-xcrun', 'xray': 'ios/arm64', 'variant': None, 'slug': 'ios',
              'carries': ['HevSocks5Tunnel', 'MontanaBindings', 'MontanaCore', 'MontanaXray', 'WebRTC']},
}


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def native_slice(framework, variant):
    info = plistlib.loads((framework / 'Info.plist').read_bytes())
    for lib in info['AvailableLibraries']:
        if lib['SupportedPlatform'] == 'ios' and lib.get('SupportedPlatformVariant') == variant and 'arm64' in lib['SupportedArchitectures']:
            return lib
    return None


def core_source(home, boundary):
    # A core named by the caller (a clone of montana_core: its core/Code) is used as it stands; otherwise the head of the core's
    # published line in the repository beside this one is archived, so an uncommitted change can never reach a release. The line, not
    # the checkout's HEAD: 2280's Mac frameworks named ae36d1f9 of a checkout on another branch, a commit montana_core does not stage
    # (stage.py pins the core to this line), and its release was refused (22.10.2026, Agent 240). The protocol core the phone carries
    # (Montana-Core) comes from the same commit, or from beside the named core.
    named = os.environ.get('MONTANA_CORE_SRC')
    if named:
        code = Path(named).resolve()
        other = Path(os.environ.get('MONTANA_BOUNDARY_SRC') or code.parent / 'Montana-Core').resolve()
        return code, other if boundary else None, {'repo': 'given', 'path': str(code.name)}
    common = Path(subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', '--path-format=absolute', '--git-common-dir'], text=True).strip())
    repo = common.parent.parent.parent / 'Montana-Protocol'
    commit = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', '--verify', CORE_LINE + '^{commit}'], text=True).strip()
    out = home / ('core-' + commit[:12])
    # The core reads its word list from beside Code/ (mt-mnemonic: include_str! of «../../../../Montana wordlist.txt»), and the public
    # core folder carries it there; measured 21.10.2026 18:37 UTC: an archive of Code/ alone could not compile mt-mnemonic.
    folders = ['Code', WORDS] + (['Montana-Core'] if boundary else [])
    if not all((out / f if f == WORDS else out / f / 'Cargo.toml').is_file() for f in folders):
        blob = subprocess.run(['git', '-C', str(repo), 'archive', '--format=tar', commit] + folders, capture_output=True, check=True).stdout
        with tarfile.open(fileobj=io.BytesIO(blob)) as tar:
            tar.extractall(out, filter='tar')
    stamp = {'repo': 'Montana-Protocol', 'commit': commit}
    for folder, key in [('Code', 'tree'), ('Montana-Core', 'boundary_tree')][:2 if boundary else 1]:
        stamp[key] = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', commit + ':' + folder], text=True).strip()
    return out / 'Code', out / 'Montana-Core' if boundary else None, dict(stamp, **{'clean': 'yes'})


def openssl(core, home, jobs, env, p):
    # The version the lock file pins, from openssl-src's own source, with the switches openssl-src gives an Apple target. The prefix
    # and the directory are compiled into the library as strings: both are the fixed name, the files go under DESTDIR.
    lock = (core / 'Cargo.lock').read_text()
    version = re.search(r'name = "openssl-src"\nversion = "([^"]+)"', lock).group(1)
    root = home / ('openssl-' + p['slug'] + '-' + version)
    out = root / FIXED.lstrip('/') / 'openssl'
    if (out / 'lib/libcrypto.a').is_file() and (out / 'lib/libssl.a').is_file():
        return out
    registry = Path(env.get('CARGO_HOME', Path.home() / '.cargo')) / 'registry/src'
    sources = [d / ('openssl-src-' + version) / 'openssl' for d in registry.iterdir() if (d / ('openssl-src-' + version)).is_dir()]
    if not sources:
        raise SystemExit('openssl-src ' + version + ' is not in the registry: run cargo fetch in the core once')
    work = Path(tempfile.mkdtemp(prefix='openssl-' + p['slug'] + '-', dir=home)) / 'openssl'
    shutil.copytree(sources[0], work)
    e = env.copy()
    e['SDKROOT'] = subprocess.check_output(['xcrun', '--sdk', p['sdk'], '--show-sdk-path'], text=True).strip()
    e['CC'] = 'clang'
    e['CFLAGS'] = '-target ' + p['triple']
    e['SOURCE_DATE_EPOCH'] = '0'
    run(['perl', './Configure', p['openssl'],
         '--prefix=' + FIXED + '/openssl', '--openssldir=' + FIXED + '/openssl/ssl', '--libdir=lib', 'no-shared', 'no-module', 'no-tests',
         'no-comp', 'no-zlib', 'no-zlib-dynamic', 'no-legacy', 'no-ssl3', 'no-md2', 'no-rc5', 'no-weak-ssl-ciphers',
         'no-camellia', 'no-idea', 'no-seed', 'no-async'], cwd=work, env=e)
    run(['make', '-j' + jobs, 'build_libs'], cwd=work, env=e)
    run(['make', 'install_dev', 'DESTDIR=' + str(root)], cwd=work, env=e)
    shutil.rmtree(work.parent)
    return out


def remapped(env, target, folders):
    cargo_home = Path(env.get('CARGO_HOME', Path.home() / '.cargo')).resolve()
    # rustc keeps the last rule that matches: the general home first, the precise folders after it
    remap = [(Path.home(), FIXED + '/home'), (cargo_home, FIXED + '/cargo')] + folders
    env['CARGO_ENCODED_RUSTFLAGS'] = chr(31).join('--remap-path-prefix=' + str(a) + '=' + b for a, b in remap)
    env['CFLAGS_' + target.replace('-', '_')] = ' '.join('-ffile-prefix-map=' + str(a) + '=' + b for a, b in remap)


def bindings(core, home, out, jobs, p, name):
    env = os.environ.copy()
    target = home / (name + '-core-target')
    env['CARGO_TARGET_DIR'] = str(target)
    env['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT
    env['MT_OPENSSL_DIR'] = str(openssl(core, home, jobs, env, p))
    remapped(env, p['target'], [(core, FIXED + '/core'), (target, FIXED + '/target')])
    # The tool reads its configuration from the directory it is called in, walking up: inside the core it merges the core's
    # RUST_TEST_THREADS (a string) with the root's (a forced table) and refuses to load at all (2272's Mac road, 21.10.2026);
    # from the build home only the root's bound stands, and the thread count is passed here anyway.
    run([RUSTUP, 'run', RUST, 'cargo', 'rustc', '--locked', '-p', 'mt-bindings', '--features', 'network',
         '--release', '--target', p['target'], '--crate-type', 'staticlib', '--manifest-path', core / 'Cargo.toml',
         '--jobs', jobs], env=env, cwd=home)
    lib = target / p['target'] / 'release/libmt_bindings.a'
    headers = home / (name + '-bindings-headers')
    shutil.rmtree(headers, ignore_errors=True)
    headers.mkdir()
    for h in ['mt_bindings.h', 'montana_ffi.h']:
        shutil.copyfile(core / 'crates/mt-bindings/include' / h, headers / h)
    (headers / 'module.modulemap').write_text('module MontanaBindings {\n header "mt_bindings.h"\n header "montana_ffi.h"\n export *\n}\n')
    run(['xcodebuild', '-create-xcframework', '-library', lib, '-headers', headers, '-output', out / 'MontanaBindings.xcframework'])


def protocol_core(boundary, home, out, jobs, p, name):
    # The phone links libmt_boundary.a and finds montana_core.h by path (OTHER_LDFLAGS and HEADER_SEARCH_PATHS of the project, under
    # MontanaCore.xcframework/ios-arm64); the framework carries the header alone -- a second module map beside MontanaBindings' gives
    # «Multiple commands produce .../include/module.modulemap» (30.08.2026)
    env = os.environ.copy()
    target = home / (name + '-boundary-target')
    env['CARGO_TARGET_DIR'] = str(target)
    env['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT
    remapped(env, p['target'], [(boundary, FIXED + '/boundary'), (target, FIXED + '/target')])
    run([RUSTUP, 'run', RUST, 'cargo', 'build', '--locked', '-p', 'mt-boundary', '--release', '--target', p['target'],
         '--manifest-path', boundary / 'Cargo.toml', '--jobs', jobs], env=env, cwd=home)
    headers = home / (name + '-boundary-headers')
    shutil.rmtree(headers, ignore_errors=True)
    headers.mkdir()
    shutil.copyfile(boundary / 'crates/mt-boundary/include/montana_core.h', headers / 'montana_core.h')
    run(['xcodebuild', '-create-xcframework', '-library', target / p['target'] / 'release/libmt_boundary.a', '-headers', headers,
         '-output', out / 'MontanaCore.xcframework'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--platform', choices=sorted(PLATFORMS), default='mac')
    parser.add_argument('--home', help='the build home (default: build/ of this tree)')
    args = parser.parse_args()
    p = PLATFORMS[args.platform]
    targets = subprocess.check_output([RUSTUP, 'target', 'list', '--installed', '--toolchain', RUST], text=True)
    if p['target'] not in targets.splitlines():
        raise SystemExit('Rust ' + RUST + ' needs the ' + p['target'] + ' target: rustup target add --toolchain ' + RUST + ' ' + p['target'])
    if not args.prepare:
        print(args.platform + ' dependencies: Rust ' + RUST + ' with ' + p['target'] + ' found; --prepare builds the frameworks')
        return
    jobs = os.environ.get('MT_CORES') or str(os.cpu_count())
    home = Path(args.home).resolve() if args.home else ROOT / 'build'
    home.mkdir(parents=True, exist_ok=True)
    # A fresh output preserves earlier artifacts and cannot mutate a framework shared with another task.
    out = Path(tempfile.mkdtemp(prefix=args.platform + '-frameworks-', dir=home))
    boundary = 'MontanaCore' in p['carries']
    core, boundary_src, stamp = core_source(home, boundary)
    if not (core / 'crates/mt-bindings/Cargo.toml').is_file():
        raise SystemExit('No mt-bindings in the core at ' + str(core))
    if boundary and not (boundary_src / 'crates/mt-boundary/Cargo.toml').is_file():
        raise SystemExit('No mt-boundary in the protocol core at ' + str(boundary_src))
    bindings(core, home, out, jobs, p, args.platform)
    if boundary:
        protocol_core(boundary_src, home, out, jobs, p, args.platform)
    if 'HevSocks5Tunnel' in p['carries']:
        run(['bash', ROOT / 'scripts/hev-ios/build-hev-xcframework.sh', home / 'hev-src', out / 'HevSocks5Tunnel.xcframework'])
    run(['bash', ROOT / 'scripts/xray-ios/build-xray-xcframework.sh', p['xray'], out / 'MontanaXray.xcframework'])
    webrtc = home / 'webrtc-144.7559.10/WebRTC.xcframework'
    run(['bash', ROOT / 'fetch-webrtc.sh', webrtc])
    (out / 'WebRTC.xcframework').symlink_to(webrtc)
    for name in p['carries']:
        if native_slice(out / (name + '.xcframework'), p['variant']) is None:
            raise SystemExit('Missing ' + args.platform + ' slice: ' + name)
    for name in ['MontanaBindings', 'MontanaCore']:
        if name in p['carries']:
            (out / (name + '.xcframework') / 'SOURCE').write_text(''.join(k + '=' + v + '\n' for k, v in stamp.items()))
    (home / (args.platform + '-frameworks.path')).write_text(str(out) + '\n')
    print(args.platform + ' frameworks ready: ' + str(out) + ' (core ' + (stamp.get('commit') or stamp['path'])[:12] + ')')


if __name__ == '__main__':
    main()
