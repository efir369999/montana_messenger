#!/bin/bash
# The core as a telephone links it: one library for the device, the header a client compiles
# against, and the framework that carries both. Nothing of it is kept in history — what a client
# links is built from this tree by whoever links it, which is what makes the boundary checkable
# rather than trusted.
#
# The toolchain is rustup's and not whatever stands first in the path: a rust installed by a
# package manager carries the standard library of the machine it runs on and none for a telephone,
# so a build against it fails at `core` rather than at anything of this tree.
#
# Two build tasks at a time, on the economical cores, because the machine belongs to the person in
# front of it.
set -euo pipefail

HERE="$(dirname "${BASH_SOURCE[0]}")"
ROOT="$(python3 -c 'import pathlib,sys;print(pathlib.Path(sys.argv[1]).resolve().parent)' "$HERE")"
CARGO="${CARGO:-$HOME/.cargo/bin/cargo}"
TARGET=aarch64-apple-ios
OUT="$ROOT/target/MontanaCore.xcframework"

if [ ! -x "$CARGO" ]; then
  echo "no cargo of rustup at $CARGO; a telephone needs the standard library rustup carries" >&2
  exit 1
fi

echo "building the boundary for $TARGET"
taskpolicy -b nice -n 19 "$CARGO" build --manifest-path "$ROOT/Cargo.toml" \
  -p mt-boundary --release --target "$TARGET" --jobs 2

LIB="$ROOT/target/$TARGET/release/libmt_boundary.a"
[ -f "$LIB" ] || { echo "the library was not built at $LIB" >&2; exit 1; }

python3 - "$ROOT" "$LIB" "$OUT" <<'PY'
import pathlib, shutil, sys
root, lib, out = (pathlib.Path(one) for one in sys.argv[1:4])
at = out / "ios-arm64"
headers = at / "Headers"
headers.mkdir(parents=True, exist_ok=True)
shutil.copy2(lib, at / lib.name)
shutil.copy2(root / "crates/mt-boundary/include/montana_core.h", headers / "montana_core.h")
plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>AvailableLibraries</key>
\t<array>
\t\t<dict>
\t\t\t<key>BinaryPath</key>
\t\t\t<string>NAME</string>
\t\t\t<key>HeadersPath</key>
\t\t\t<string>Headers</string>
\t\t\t<key>LibraryIdentifier</key>
\t\t\t<string>ios-arm64</string>
\t\t\t<key>LibraryPath</key>
\t\t\t<string>NAME</string>
\t\t\t<key>SupportedArchitectures</key>
\t\t\t<array>
\t\t\t\t<string>arm64</string>
\t\t\t</array>
\t\t\t<key>SupportedPlatform</key>
\t\t\t<string>ios</string>
\t\t</dict>
\t</array>
\t<key>CFBundlePackageType</key>
\t<string>XFWK</string>
\t<key>XCFrameworkFormatVersion</key>
\t<string>1.0</string>
</dict>
</plist>
""".replace("NAME", lib.name)
(out / "Info.plist").write_text(plist, encoding="utf-8")
print("the framework stands at", out)
print("  the library is", (at / lib.name).stat().st_size // (1024 * 1024), "MiB")
PY
