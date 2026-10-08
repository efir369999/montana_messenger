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
  echo "core in place: $OUT"
else
  echo "built framework not found; check $CORE_SRC/build-ios-xcframework.sh output" >&2
  exit 1
fi
