"""Where the tools of scripts/toolchain.json live on this computer, read by setup.py, build.py and lauterbourg.py."""
import json
import os
import platform
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PIN = json.load(open(os.path.join(HERE, "toolchain.json"), encoding="utf-8"))


def host():
    system, machine = platform.system(), platform.machine()
    if (system, machine) == ("Darwin", "arm64"):
        return "macos-aarch64"
    if (system, machine) == ("Linux", "x86_64"):
        return "linux-x86_64"
    raise SystemExit("no toolchain for %s %s: scripts/toolchain.json knows macOS on Apple silicon and Linux x86-64"
                     % (system, machine))


class Paths:
    def __init__(self):
        self.host = host()
        place = PIN["hosts"][self.host]
        self.tools = os.path.expanduser(place["tools"])
        self.sdk = os.path.expanduser(place["sdk"])
        self.rustup_home = os.path.expanduser(place["rustup_home"])
        self.cargo_home = os.path.expanduser(place["cargo_home"])
        self.jdk = os.path.join(self.tools, "jdk-17")
        # the macOS JDK is an app bundle; its home is inside
        self.java_home = os.path.join(self.jdk, "Contents", "Home") if self.host.startswith("macos") else self.jdk
        self.kotlinc_dir = os.path.join(self.tools, "kotlinc")
        self.kotlinc = os.path.join(self.kotlinc_dir, "bin", "kotlinc")
        self.stdlib = os.path.join(self.kotlinc_dir, "lib", "kotlin-stdlib.jar")
        self.sdkmanager = os.path.join(self.sdk, "cmdline-tools", "latest", "bin", "sdkmanager")
        self.build_tools = os.path.join(self.sdk, "build-tools", PIN["build_tools"])
        self.android_jar = os.path.join(self.sdk, "platforms", PIN["platform"], "android.jar")
        self.ndk = os.path.join(self.sdk, "ndk", PIN["ndk"])
        self.adb = os.path.join(self.sdk, "platform-tools", "adb")
        self.webrtc = os.path.join(self.tools, "webrtc", "android-%s.aar" % PIN["webrtc"]["version"])
        self.protocol = os.path.normpath(os.path.join(ROOT, PIN["protocol"]["dir"]))

    def env(self):
        e = dict(os.environ)
        e.update(JAVA_HOME=self.java_home, ANDROID_HOME=self.sdk, ANDROID_NDK_HOME=self.ndk,
                 RUSTUP_HOME=self.rustup_home, CARGO_HOME=self.cargo_home)
        e["PATH"] = os.pathsep.join([os.path.join(self.java_home, "bin"), os.path.join(self.cargo_home, "bin"),
                                     e.get("PATH", "")])
        return e

    def tool(self, name):
        # the host's own Rust home first (the shared host keeps its toolchain there), then whatever this computer has
        own = os.path.join(self.cargo_home, "bin", name)
        return own if os.path.exists(own) else (shutil.which(name) or name)

    def rust_channel(self):
        # the core pins its compiler; the Android library is built with the very same one
        pin = os.path.join(self.protocol, "Code", "rust-toolchain.toml")
        for line in open(pin, encoding="utf-8"):
            key, _, value = line.partition("=")
            if key.strip() == "channel":
                return value.strip().strip('"')
        raise SystemExit("no channel in " + pin)
