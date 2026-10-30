#!/usr/bin/env bash
# THE AUTHOR FIELD'S SELF-CHECK ON EVERY DAY (app/.../AuthorCanon.kt): tools/author_vectors.py re-derives the vectors from the iOS
# formula outside the app, and tools/author_canon_check.kt runs the self-check on chosen days over a mirror of the code Wire signs with.
# Runs in WSL: tools/author_canon_check.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
work="${TMPDIR:-/tmp}/montana-author-canon-check"
export JAVA_HOME=/opt/montana-tools/jdk-17
kotlinc=/opt/montana-tools/kotlinc/bin/kotlinc
rm -rf "$work"; mkdir -p "$work"
python3 -I -X utf8 "$here/author_vectors.py"
JAVA_OPTS="-Xmx1g" "$kotlinc" -nowarn "$root/app/src/main/kotlin/quest/montana/app/AuthorCanon.kt" "$here/author_canon_check.kt" \
    -include-runtime -d "$work/check.jar" 2>&1 | grep -v '^warning' || true
"$JAVA_HOME/bin/java" -jar "$work/check.jar"
echo "AUTHOR CANON CHECK PASSED"
