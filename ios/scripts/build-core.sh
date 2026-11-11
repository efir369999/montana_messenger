#!/bin/bash
# Montana core for the client: one core, built from the protocol tree, never stored in history.
# Usage: scripts/build-core.sh
set -euo pipefail

CORE_SRC="${MONTANA_CORE_SRC:-$HOME/Python/Nothing/Montana/Montana-Protocol/Code/crates/mt-bindings}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$HERE/Code/Frameworks/MontanaBindings.xcframework"

if [ ! -d "$CORE_SRC" ]; then
  echo "core source not found: $CORE_SRC" >&2
  echo "set MONTANA_CORE_SRC to the mt-bindings crate" >&2
  exit 1
fi

echo "building core from $CORE_SRC"
bash "$CORE_SRC/build-ios-xcframework.sh"

BUILT="$(dirname "$CORE_SRC")/../target/MontanaBindings.xcframework"
[ -d "$BUILT" ] || BUILT="$CORE_SRC/pkg/MontanaBindings.xcframework"
if [ -d "$BUILT" ]; then
  rsync -a --delete "$BUILT/" "$OUT/"
  # THE FRAMEWORK SAYS WHAT IT WAS BUILT FROM (the author's words 16.10.2026 15:2x UTC: "the core must always be current there with
  # the build versions 1.0 (number)", "the client carries the core"): the commit of the core's tree and whether that tree held
  # uncommitted changes stand beside the framework, so the publisher shows on GitHub the core every build of this client carries.
  CORE_REPO="$(git -C "$CORE_SRC" rev-parse --show-toplevel)"
  {
    echo "repo=$CORE_REPO"
    echo "commit=$(git -C "$CORE_REPO" rev-parse HEAD)"
    if [ -z "$(git -C "$CORE_REPO" status --porcelain --untracked-files=no)" ]; then echo "clean=yes"; else echo "clean=no"; fi
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$OUT/SOURCE"
  echo "core in place: $OUT"
else
  echo "built framework not found; check $CORE_SRC/build-ios-xcframework.sh output" >&2
  exit 1
fi
