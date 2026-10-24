#!/bin/sh
# The build is one road on every computer: scripts/build.py (docs/BUILD.md).
exec python3 "$(dirname "$0")/build.py" "$@"
