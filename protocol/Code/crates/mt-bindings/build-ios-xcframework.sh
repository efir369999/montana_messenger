#!/bin/bash
# Rebuild MontanaBindings.xcframework (device-only arm64) with --features network.
# The header's one source: include/montana_ffi.h (kept by hand) plus mt_bindings.h; Montana's edition adds mt_coin.h.
# THE EDITION (OZ1 S5-core-3): MT_EDITION=messenger builds the bindings without the coins (--no-default-features,
# decision D1) and ships without mt_coin.h; its framework lands in Code/target/messenger/.
# Montana's edition is the default.
# THE OUTPUT IS THE CALLER'S, OR THE PLACE EVERY CLIENT TAKES IT FROM (10.10.2026): the first argument names a framework that
# does not exist yet; without it the framework lands in Code/target/MontanaBindings.xcframework, where each client's
# scripts/build-core.sh reads it. The path written here before named a folder of one Mac that no longer exists, so a client
# built from the public tree stopped at «built framework not found».
set -euo pipefail
cd "$(dirname "$0")"
ROOT="../.."
EDITION="${MT_EDITION:-montana}"
case "$EDITION" in
  montana)   FEATURES=(--features network);                       HEADERS=(mt_bindings.h montana_ffi.h mt_coin.h) ;;
  messenger) FEATURES=(--no-default-features --features network); HEADERS=(mt_bindings.h montana_ffi.h) ;;
  *) echo "REFUSED: MT_EDITION is montana or messenger" >&2; exit 2 ;;
esac
if [ -n "${1:-}" ]; then
  OUT_XC="$1"
  if [ -e "$OUT_XC" ]; then
    echo "REFUSED: $OUT_XC exists; set it aside first" >&2
    exit 2
  fi
else
  OUT_XC="$(cd "$ROOT" && pwd)/target/MontanaBindings.xcframework"
  if [ "$EDITION" = messenger ]; then OUT_XC="$(cd "$ROOT" && pwd)/target/messenger/MontanaBindings.xcframework"; fi
  mkdir -p "$(dirname "$OUT_XC")"
  rm -rf "$OUT_XC"   # the core's own build folder: the framework built here the last time
fi

# The header include/montana_ffi.h is kept by hand (patches): cbindgen 0.29.4 regresses the opaque typedef
# (WakeRegistry), so it is never regenerated here.

# THE SAME BYTES FROM ANY FOLDER (decision 822 a, 11.11.2026): the library carries no path of this Mac. The tree is named
# /montana and cargo's home /cargo in every file name the compiler writes; OpenSSL builds in one fixed folder (its install
# folder is written into the library) and its «built on» is the epoch, not the clock: the repository a stranger clones has
# commits of its own times, so no time of a commit could stand there. So anyone who builds this
# commit, in any folder, gets the library the App Store build carries, byte for byte. One release build at a time: the
# OpenSSL folder is shared. The tree's path is the physical one (pwd -P): the compiler sees /private/tmp, not /tmp.
TREE="$(cd "$ROOT/.." && pwd -P)"
export CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=$TREE=/montana"$'\x1f'"--remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo"
# The C the crates carry (ring builds its C and assembly with debug info always) is told the same two names; the flags are
# shell-quoted, so a folder with a space stays one flag. OpenSSL writes its compiler flags into the library, so mt-crypto-native
# hands it none of these (its folder is fixed already).
export CC_SHELL_ESCAPED_FLAGS=1
export TARGET_CFLAGS="'-ffile-prefix-map=$TREE=/montana' '-ffile-prefix-map=${CARGO_HOME:-$HOME/.cargo}=/cargo'"
export MT_OPENSSL_BUILD_DIR=/tmp/montana-openssl
export SOURCE_DATE_EPOCH=0

echo "[1/3] cargo build device (device only, no simulator) (aarch64-apple-ios), edition $EDITION"
# Cargo reads every .cargo/config.toml from the directory it starts in upwards; inside Code/ the workspace's own file and
# one above the tree may disagree on env.RUST_TEST_THREADS and cargo stops. From Code/'s parent the workspace's file is not
# read (it bounds only the jobs and the test threads) and the manifest is named.
( cd "$ROOT/.." && rustup run 1.92.0 cargo rustc --manifest-path Code/Cargo.toml -p mt-bindings "${FEATURES[@]}" --release --target aarch64-apple-ios --crate-type staticlib )

echo "[2/3] headers dir + modulemap"
HDIR="$(mktemp -d)"
for h in "${HEADERS[@]}"; do cp "include/$h" "$HDIR/"; done
{
  echo "module MontanaBindings {"
  for h in "${HEADERS[@]}"; do echo "    header \"$h\""; done
  echo "    export *"
  echo "}"
} > "$HDIR/module.modulemap"

echo "[3/3] create xcframework: $OUT_XC"
xcodebuild -create-xcframework \
  -library "$ROOT/target/aarch64-apple-ios/release/libmt_bindings.a" -headers "$HDIR" \
  -output "$OUT_XC"
# THE FRAMEWORK SAYS WHAT IT WAS BUILT FROM (as scripts/build-protocol-core.sh stamps MontanaCore; Agent 975, 05.11.2026): the
# commit of this tree, whether it held uncommitted changes and the edition stand beside the framework, so the publisher stages
# the core the build carries (publish_build.py carried_core; the Messenger's store repository, store_build.py).
CORE_REPO="$(git -C "$ROOT" rev-parse --show-toplevel)"
{
  echo "repo=$CORE_REPO"
  echo "commit=$(git -C "$CORE_REPO" rev-parse HEAD)"
  if [ -z "$(git -C "$CORE_REPO" status --porcelain --untracked-files=no)" ]; then echo "clean=yes"; else echo "clean=no"; fi
  echo "edition=$EDITION"
  echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$OUT_XC/SOURCE"
echo "DONE xcframework"
