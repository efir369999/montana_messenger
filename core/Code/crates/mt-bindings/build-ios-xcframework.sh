#!/bin/bash
# Rebuild MontanaBindings.xcframework (device-only arm64) with --features network.
# The header's one source: include/montana_ffi.h (kept by hand) plus mt_bindings.h.
# THE OUTPUT IS THE CALLER'S, OR THE PLACE EVERY CLIENT TAKES IT FROM (10.10.2026): the first argument names a framework that
# does not exist yet; without it the framework lands in Code/target/MontanaBindings.xcframework, where each client's
# scripts/build-core.sh reads it. The path written here before named a folder of one Mac that no longer exists, so a client
# built from the public tree stopped at «built framework not found».
set -euo pipefail
cd "$(dirname "$0")"
ROOT="../.."
if [ -n "${1:-}" ]; then
  OUT_XC="$1"
  if [ -e "$OUT_XC" ]; then
    echo "REFUSED: $OUT_XC exists; set it aside first" >&2
    exit 2
  fi
else
  OUT_XC="$(cd "$ROOT" && pwd)/target/MontanaBindings.xcframework"
  rm -rf "$OUT_XC"   # the core's own build folder: the framework built here the last time
fi

# The header include/montana_ffi.h is kept by hand (patches): cbindgen 0.29.4 regresses the opaque typedef
# (WakeRegistry), so it is never regenerated here.

echo "[1/3] cargo build device (device only, no simulator) (aarch64-apple-ios)"
# Cargo reads every .cargo/config.toml from the directory it starts in upwards; inside Code/ the workspace's own file and
# one above the tree may disagree on env.RUST_TEST_THREADS and cargo stops. From Code/'s parent the workspace's file is not
# read (it bounds only the jobs and the test threads) and the manifest is named.
( cd "$ROOT/.." && rustup run 1.92.0 cargo rustc --manifest-path Code/Cargo.toml -p mt-bindings --features network --release --target aarch64-apple-ios --crate-type staticlib )

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

echo "[3/3] create xcframework: $OUT_XC"
xcodebuild -create-xcframework \
  -library "$ROOT/target/aarch64-apple-ios/release/libmt_bindings.a" -headers "$HDIR" \
  -output "$OUT_XC"
echo "DONE xcframework"
