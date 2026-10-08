#!/usr/bin/env python3
"""Installs the toolchain of scripts/toolchain.json on this computer: the JDK, the Android SDK pieces, the Kotlin compiler,
the call engine (WebRTC), and the core's road (the NDK, the core's own Rust with the phone's target, cargo-ndk).

usage: python3 scripts/setup.py [--apk-only]
  --apk-only   all but the core's road: for a computer that writes and checks the Kotlin and installs on a phone,
               while the core is built on the shared host (docs/BUILD.md)

A piece already in place is left as it is; a piece of another version stops the setup with its name. Every download
is checked against the digest pinned in toolchain.json before it is unpacked."""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request

import toolchain

PIN = toolchain.PIN
CHUNK = 1048576


def say(text):
    print("setup: " + text, flush=True)


def run(args, env=None, feed=None):
    r = subprocess.run(args, env=env, input=feed)
    if r.returncode:
        raise SystemExit("setup: failed (%d): %s" % (r.returncode, " ".join(args)))


def fetch(url, algo, digest, into):
    say("download " + url)
    h = hashlib.new(algo)
    req = urllib.request.Request(url, headers={"User-Agent": "montana-setup"})
    with urllib.request.urlopen(req, timeout=120) as r, open(into, "wb") as f:
        while True:
            chunk = r.read(CHUNK)
            if not chunk:
                break
            h.update(chunk)
            f.write(chunk)
    if h.hexdigest() != digest:
        raise SystemExit("setup: digest mismatch for %s: %s, pinned %s" % (url, h.hexdigest(), digest))


def unpack(url, algo, digest, inner, target):
    # unpacked beside the target, then put in place whole: a broken download never leaves half a tool
    parent = os.path.dirname(target)
    os.makedirs(parent, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=parent) as tmp:
        archive = os.path.join(tmp, url.rsplit("/", 1)[1])
        fetch(url, algo, digest, archive)
        out = os.path.join(tmp, "out")
        os.makedirs(out)
        if archive.endswith(".zip"):
            run(["unzip", "-q", archive, "-d", out])
        else:
            run(["tar", "-xzf", archive, "-C", out])
        os.rename(os.path.join(out, inner), target)


def jdk(p):
    pin = PIN["jdk"]
    version = pin["release"][len("jdk-"):]
    if os.path.isdir(p.jdk):
        found = open(os.path.join(p.java_home, "release"), encoding="utf-8").read()
        if version not in found:
            raise SystemExit("setup: %s holds another JDK; set it aside and run again (pinned %s)" % (p.jdk, version))
        return say("JDK %s in place" % version)
    unpack(pin[p.host]["url"], "sha256", pin[p.host]["sha256"], pin["release"], p.jdk)
    say("JDK %s installed" % version)


def cmdline_tools(p):
    pin = PIN["cmdline_tools"]
    home = os.path.dirname(os.path.dirname(p.sdkmanager))
    if os.path.exists(p.sdkmanager):
        props = open(os.path.join(home, "source.properties"), encoding="utf-8").read()
        if "Pkg.Revision=" + pin["revision"] not in props:
            raise SystemExit("setup: %s holds other command-line tools; set them aside and run again (pinned %s: %s)"
                             % (home, pin["revision"], pin["why"]))
        return say("Android command-line tools %s in place" % pin["revision"])
    unpack(pin[p.host]["url"], "sha1", pin[p.host]["sha1"], "cmdline-tools", home)
    say("Android command-line tools %s installed" % pin["revision"])


def sdk_packages(p, core):
    want = ["build-tools;" + PIN["build_tools"], "platforms;" + PIN["platform"], "platform-tools"]
    if core:
        want.append("ndk;" + PIN["ndk"])
    missing = [w for w in want if not os.path.isdir(os.path.join(p.sdk, w.replace(";", os.sep)))]
    if not missing:
        return say("SDK packages in place: " + ", ".join(want))
    answers = ""
    for _ in range(64):
        answers += "y\n"
    tool = [p.sdkmanager, "--sdk_root=" + p.sdk]
    run(tool + ["--licenses"], env=p.env(), feed=answers.encode())
    run(tool + missing, env=p.env(), feed=answers.encode())
    say("SDK packages installed: " + ", ".join(missing))


def kotlin(p):
    pin = PIN["kotlin"]
    stamp = os.path.join(p.kotlinc_dir, "build.txt")
    if os.path.isdir(p.kotlinc_dir):
        found = open(stamp, encoding="utf-8").read() if os.path.exists(stamp) else "unknown"
        if not found.startswith(pin["version"]):
            raise SystemExit("setup: %s holds Kotlin %s; set it aside and run again (pinned %s)"
                             % (p.kotlinc_dir, found.strip(), pin["version"]))
        return say("Kotlin %s in place" % pin["version"])
    unpack(pin["url"], "sha256", pin["sha256"], "kotlinc", p.kotlinc_dir)
    say("Kotlin %s installed" % pin["version"])


def digest_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(CHUNK)
            if not chunk:
                return h.hexdigest()
            h.update(chunk)


def webrtc(p):
    pin = PIN["webrtc"]
    if os.path.exists(p.webrtc):
        if digest_of(p.webrtc) != pin["sha256"]:
            raise SystemExit("setup: %s is not the pinned call engine; set it aside and run again (pinned %s)"
                             % (p.webrtc, pin["version"]))
        return say("WebRTC %s in place" % pin["version"])
    parent = os.path.dirname(p.webrtc)
    os.makedirs(parent, exist_ok=True)
    # downloaded beside its place, then put there whole: a broken download never leaves half an engine
    with tempfile.TemporaryDirectory(dir=parent) as tmp:
        got = os.path.join(tmp, os.path.basename(p.webrtc))
        fetch(pin["url"], "sha256", pin["sha256"], got)
        os.rename(got, p.webrtc)
    say("WebRTC %s installed" % pin["version"])


def rust(p):
    channel, env = p.rust_channel(), p.env()
    rustup = p.tool("rustup")
    if rustup == "rustup" and not shutil.which("rustup"):
        # no rustup on this computer: the official installer, into this host's pinned homes, no shell profile touched
        req = urllib.request.Request("https://sh.rustup.rs", headers={"User-Agent": "montana-setup"})
        script = urllib.request.urlopen(req, timeout=60).read()
        run(["sh", "-s", "--", "-y", "--no-modify-path", "--profile", "minimal", "--default-toolchain", channel],
            env=env, feed=script)
        rustup = p.tool("rustup")
    run([rustup, "toolchain", "install", channel, "--profile", "minimal"], env=env)
    run([rustup, "target", "add", "--toolchain", channel, "aarch64-linux-android"], env=env)
    cargo = p.tool("cargo")
    have = subprocess.run([cargo, "ndk", "--version"], env=env, capture_output=True, text=True).stdout
    if PIN["cargo_ndk"] not in have:
        run([cargo, "+" + channel, "install", "cargo-ndk", "--version", PIN["cargo_ndk"], "--locked"], env=env)
    say("Rust %s with aarch64-linux-android and cargo-ndk %s in place" % (channel, PIN["cargo_ndk"]))


def main():
    args = sys.argv[1:]
    if args not in ([], ["--apk-only"]):
        raise SystemExit(__doc__)
    core = not args
    p = toolchain.Paths()
    if p.host.startswith("linux"):
        # the shared host: the prefix belongs to the builders' group (setgid), and every builder writes in it
        os.umask(0o002)
    os.makedirs(p.tools, exist_ok=True)
    os.makedirs(p.sdk, exist_ok=True)
    jdk(p)
    cmdline_tools(p)
    sdk_packages(p, core)
    kotlin(p)
    webrtc(p)
    if core:
        rust(p)
    say("ready on %s%s" % (p.host, "" if core else " (the core is built on the shared host)"))


if __name__ == "__main__":
    main()
