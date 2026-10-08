#!/usr/bin/env bash
# Spec Conformance Harness gate — role CLAUDE.md [C-14].
# Prints the conformance ledger and exits non-zero on any spec-code drift,
# incompleteness, or version-stamp divergence. Release turnstile.
set -euo pipefail
cd "$(dirname "$0")/.."
exec cargo run --quiet --release -p mt-conformance --bin conformance-gate
