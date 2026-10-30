#!/usr/bin/env bash
# THE LZFSE OF THE COIN VAULT AGAINST THE REFERENCE (app/.../Lzfse.kt; iOS packs the vault's pieces with Apple's LZFSE):
# the reference CLI (Ubuntu's lzfse 1.0, the code Apple published) encodes every input and Kotlin opens it -- bvx-, bvxn and bvx2
# blocks, and the bvx2 ones again as bvx1 -- Kotlin encodes every input and the reference opens it, and damaged streams are refused
# without a throw. Runs in WSL: tools/lzfse_check.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
work="${TMPDIR:-/tmp}/montana-lzfse-check"
lzfse="$(command -v lzfse || true)"
[ -n "$lzfse" ] || { echo "lzfse CLI missing: sudo apt-get install lzfse"; exit 2; }
export JAVA_HOME=/opt/montana-tools/jdk-17
kotlinc=/opt/montana-tools/kotlinc/bin/kotlinc
rm -rf "$work"; mkdir -p "$work/in"
python3 -I "$here/lzfse_inputs.py" "$work/in"
# the reference CLI frees twice on an empty input (lzfse_main.c 1.0): the stream of nothing is the end alone
for f in "$work/in"/*.bin; do
    if [ -s "$f" ]; then "$lzfse" -encode -i "$f" -o "${f%.bin}.ref"; else printf 'bvx$' > "${f%.bin}.ref"; fi
done
python3 -I "$here/lzfse_inputs.py" --damage "$work/in"
python3 -I - "$work/in" <<'EOF'
import sys, pathlib, collections
seen = collections.Counter()
for r in pathlib.Path(sys.argv[1]).glob("*.ref"):
    s, p = r.read_bytes(), 0
    while s[p:p + 4] != b"bvx$":
        m = s[p:p + 4]; seen[m.decode()] += 1
        if m == b"bvx-": p += 8 + int.from_bytes(s[p + 4:p + 8], "little")
        elif m == b"bvxn": p += 12 + int.from_bytes(s[p + 8:p + 12], "little")
        else:
            v0, v1, v2 = (int.from_bytes(s[p + o:p + o + 8], "little") for o in (8, 16, 24))
            p += (v2 & 0xFFFFFFFF) + ((v0 >> 20) & 0xFFFFF) + ((v1 >> 40) & 0xFFFFF)
print("reference blocks:", dict(seen))
EOF
"$kotlinc" -nowarn "$root/app/src/main/kotlin/quest/montana/app/Lzfse.kt" "$here/lzfse_check.kt" -include-runtime -d "$work/check.jar" 2>&1 | grep -v '^warning' || true
"$JAVA_HOME/bin/java" -jar "$work/check.jar" "$work/in"
n=0
for f in "$work/in"/*.kt; do
    if [ ! -s "${f%.kt}.bin" ]; then
        [ "$(cat "$f")" = 'bvx$' ] || { echo "FAIL the stream of nothing ${f##*/}"; exit 1; }
        n=$((n + 1)); continue
    fi
    "$lzfse" -decode -i "$f" -o "${f%.kt}.back"
    cmp -s "${f%.kt}.back" "${f%.kt}.bin" || { echo "FAIL the reference cannot open ${f##*/}"; exit 1; }
    n=$((n + 1))
done
echo "reference opened all $n Kotlin streams"
echo "LZFSE CHECK PASSED"
