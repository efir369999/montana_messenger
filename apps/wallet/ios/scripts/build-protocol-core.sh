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
echo "the protocol core stands at $OUT"
