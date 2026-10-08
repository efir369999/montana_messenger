#!/bin/bash
# Rebuild MontanaBindings.xcframework (device-only arm64) with --features network.
# Header SSOT: cbindgen (montana_ffi.h) + hand-written mt_bindings.h. Run from crates/mt-bindings.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="../.."
OUT_XC="${OUT_XC:-$PWD/build/MontanaBindings.xcframework}"

# include/montana_ffi.h is maintained by hand (patches): cbindgen 0.29.4 regresses the
# opaque typedef (WakeRegistry). Regeneration is NOT run automatically.

echo "[1/3] cargo build device (device only, no simulator) (aarch64-apple-ios)"
( cd "$ROOT" && rustup run 1.92.0 cargo rustc -p mt-bindings --features network --release --target aarch64-apple-ios --crate-type staticlib )

echo "[2/3] headers dir + modulemap"
HDIR="$(mktemp -d)"
cp include/montana_ffi.h include/mt_bindings.h "$HDIR/"
cat > "$HDIR/module.modulemap" <<'EOF'
module MontanaBindings {
    header "mt_bindings.h"
    header "montana_ffi.h"
    export *
}
EOF

echo "[3/3] create xcframework → $OUT_XC"
rm -rf "$OUT_XC"
xcodebuild -create-xcframework \
  -library "$ROOT/target/aarch64-apple-ios/release/libmt_bindings.a" -headers "$HDIR" \
  -output "$OUT_XC"
echo "DONE xcframework"
