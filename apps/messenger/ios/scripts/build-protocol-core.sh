#!/bin/bash
# The protocol core for this client: built from the tree that owns it and copied in, never stored
# in history. What a client links is built by whoever links it.
set -euo pipefail

CORE_SRC="${MONTANA_PROTOCOL_CORE:-$HOME/Python/Nothing/Montana/Montana-Protocol/Montana-Core}"
HERE="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"
OUT="$HERE/Code/Frameworks/MontanaCore.xcframework"

[ -d "$CORE_SRC" ] || { echo "the core tree is not at $CORE_SRC" >&2; exit 1; }
bash "$CORE_SRC/tools/build-for-a-telephone.sh"

BUILT="$CORE_SRC/target/MontanaCore.xcframework"
[ -d "$BUILT" ] || { echo "the framework was not built at $BUILT" >&2; exit 1; }
python3 -c 'import shutil,sys;shutil.copytree(sys.argv[1],sys.argv[2],dirs_exist_ok=True)' "$BUILT" "$OUT"
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
echo "the protocol core stands at $OUT"
