#!/usr/bin/env bash
# Builds Montana for Android (apps/messenger/android-dinetpda) on Linux x86-64 (WSL2 on Windows).
#
#   tools/wsl-build.sh setup [--apk-only]   scripts/setup.py: the pinned toolchain into /opt/montana-tools
#   tools/wsl-build.sh test-core            cargo test of the core crates the app links, on the Linux host
#   tools/wsl-build.sh test-jni             cargo test of montana-jni: each JNI function against the iOS C function
#   tools/wsl-build.sh check                scripts/build.py --check: resources and Kotlin compile
#   tools/wsl-build.sh apk [build.py args]  scripts/build.py: the signed APK, copied to out/
#                      [--coin-writes]      the build for the owner's own test of the coins: the chains' writes on
#                                           (res coin_writes=true in the copy only), the APK named Montana-…-coins-…;
#                                           never installed on the test emulators
#   tools/wsl-build.sh identity-ref FILE    the person's own reference (twin) of the 24 words in FILE, by the core
#
# The checkout is the source of truth (on Windows it is seen here under /mnt/c). The build runs in a copy on the Linux
# filesystem, MONTANA_BUILD_DIR or ~/montana-build: OpenSSL's build breaks on paths with spaces, and /mnt/c is slow.
# The copy holds what the build reads: the repository's git data (the build checks core/ against its committed tree),
# core/ and this folder. The checkout is therefore a plain clone, its .git a folder (a git worktree's .git is a file that
# names a path of the host). The APK and the log of every run come back to out/ in this folder.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"     # this folder: apps/messenger/android-dinetpda of the repository
SRC="$(cd "$HERE/../../.." && pwd)"          # the repository
APP="${HERE#"$SRC"/}"
DST="${MONTANA_BUILD_DIR:-$HOME/montana-build}"
TOOLS=/opt/montana-tools
OUT="$HERE/out"

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
  setup|test-core|test-jni|check|apk|identity-ref) ;;
  *) sed -n '3,12p' "$0"; exit 2 ;;
esac
if [ ! -d "$SRC/.git" ] || [ ! -f "$SRC/core/Code/rust-toolchain.toml" ]; then
  echo "no plain clone with core/ three folders above $HERE (a git worktree is not copied)"; exit 2
fi

mkdir -p "$OUT/logs"
log="$OUT/logs/$cmd-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$log") 2>&1
echo "== $cmd $* | $(date -Is) | $SRC ($APP) -> $DST"

# The copy: the git data, core/ and this folder, without their build outputs, which stay in the copy between runs (cargo's
# incremental state). The rest of the repository is not copied.
mkdir -p "$DST"
rsync -a --delete \
  --exclude "/$APP/out/" \
  --exclude "/$APP/build/" \
  --exclude "/$APP/native/montana-jni/target/" \
  --exclude "/$APP/tools/identity-ref/target/" \
  --exclude '/core/Code/target/' \
  --include '/.git/***' \
  --include '/core/***' \
  --include '/apps/' \
  --include '/apps/messenger/' \
  --include "/$APP/***" \
  --exclude '*' \
  "$SRC/" "$DST/"
dirty=""
[ -n "$(git -C "$DST" -c core.fileMode=false status --porcelain --untracked-files=no -- core "$APP")" ] && dirty="-dirty"
echo "tree: $(git -C "$DST" log -1 --format='%h %s')$dirty"

# The core's Rust, in the toolchain's own homes (scripts/toolchain.json, hosts.linux-x86_64).
export RUSTUP_HOME="$TOOLS/rustup" CARGO_HOME="$TOOLS/cargo"
export PATH="$CARGO_HOME/bin:$PATH"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-8}"
channel="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$DST/core/Code/rust-toolchain.toml")"

case "$cmd" in
  setup)
    cd "$DST/$APP"
    python3 scripts/setup.py "$@"
    ;;
  test-core)
    cd "$DST/core/Code"
    cargo +"$channel" test --release \
      -p mt-mnemonic -p mt-crypto -p mt-crypto-native -p mt-codec \
      -p mt-noise-pq -p mt-names -p mt-messenger-e2e -p mt-bindings "$@"
    ;;
  test-jni)
    cd "$DST/$APP/native/montana-jni"
    cargo +"$channel" test --release "$@"
    ;;
  check)
    cd "$DST/$APP"
    python3 scripts/build.py --check "$@"
    ;;
  apk)
    cd "$DST/$APP"
    # THE COINS' WRITES, ONLY WHERE ASKED (CoinTx.WRITES): the copy's flag turned on for this one build; the next rsync puts it back
    args=(); coins=""
    for a in "$@"; do if [ "$a" = "--coin-writes" ]; then coins="-coins"; else args+=("$a"); fi; done
    if [ -n "$coins" ]; then
      flags="$DST/$APP/app/src/main/res/values/coin_flags.xml"
      sed -i 's|<bool name="coin_writes">false</bool>|<bool name="coin_writes">true</bool>|' "$flags"
      grep -q '<bool name="coin_writes">true</bool>' "$flags" || { echo "coin writes: the flag did not turn"; exit 1; }
      echo "coin writes: ON for this build"
    fi
    python3 scripts/build.py "${args[@]}"
    apk="$DST/$APP/build/Montana.apk"
    abis="$(unzip -Z1 "$apk" 'lib/*' | cut -d/ -f2 | sort -u | paste -sd+ -)"
    name="Montana-$(git -C "$DST" rev-parse --short HEAD)$dirty$coins-$abis.apk"
    cp "$apk" "$OUT/$name"
    (cd "$OUT" && sha256sum "$name" | tee "$name.sha256")
    echo "APK: out/$name"
    ;;
  identity-ref)
    words="$(readlink -f "$1")"
    cd "$DST/$APP/tools/identity-ref"
    echo "twin of $(basename "$words"): $(cargo +"$channel" run --release -q -- "$words")"
    ;;
esac
echo "== done: $cmd | $(date -Is) | log: out/logs/$(basename "$log")"
