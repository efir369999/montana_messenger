#!/bin/bash
# Montana node-only entrypoint. The genesis manifest is mounted from the
# host (never baked into the image), so a node's genesis is decoupled from the
# binary and cannot silently drift between machines.
#
# Env:
#   MONTANA_LISTEN              default /ip4/0.0.0.0/tcp/8444
#   MONTANA_MNEMONIC           fixed identity (otherwise generated on first run)
#   MONTANA_GENESIS_MANIFEST   manifest path (default /etc/montana/genesis-manifest.json)
#   MONTANA_MANIFEST_SHA256    if set, refuse to start unless manifest sha matches
#   MONTANA_D_TEST_OVERRIDE    TEST-ONLY fast SSHA (same value across the cohort)
set -euo pipefail

DATA_DIR="/var/lib/montana"
MANIFEST="${MONTANA_GENESIS_MANIFEST:-/etc/montana/genesis-manifest.json}"
LISTEN="${MONTANA_LISTEN:-/ip4/0.0.0.0/tcp/8444}"

mkdir -p "$DATA_DIR"
chown -R montana:montana "$DATA_DIR"

# 1. Generate identity once per data volume.
if [ ! -f "$DATA_DIR/identity.bin" ]; then
  echo "[entrypoint] first run on this volume — generating node identity"
  # Create the recovery output owner-only before init writes anything. Never overwrite
  # a prior recovery artifact, including one left by an unsuccessful initialization.
  if [ -e "$DATA_DIR/mnemonic.txt" ] || [ -L "$DATA_DIR/mnemonic.txt" ]; then
    echo "[entrypoint] recovery output already exists; inspect the volume before initializing" >&2
    exit 1
  fi
  (
    umask 0377
    set -C
    exec > "$DATA_DIR/mnemonic.txt" 2>&1
    chown montana:montana "$DATA_DIR/mnemonic.txt"
    umask 0077 # The private recovery file is already open; init may create directories.
    # init can write to /dev/tty. Detach from the container terminal, and keep
    # both output streams in the private file even on failure. setsid --wait
    # preserves the init exit status; a failed init must never start the node.
    if [ -n "${MONTANA_MNEMONIC:-}" ]; then
      printf '%s\n' "$MONTANA_MNEMONIC" | (
        unset MONTANA_MNEMONIC
        exec runuser -u montana -- setsid --wait /usr/local/bin/montana-node init --data-dir "$DATA_DIR" --mnemonic-stdin
      )
    else
      unset MONTANA_MNEMONIC
      runuser -u montana -- setsid --wait /usr/local/bin/montana-node init --data-dir "$DATA_DIR"
    fi
  )
fi

unset MONTANA_MNEMONIC

# 2. Optional manifest pin — refuse to start on sha mismatch (anti-drift).
if [ -f "$MANIFEST" ] && [ -n "${MONTANA_MANIFEST_SHA256:-}" ]; then
  actual="$(sha256sum "$MANIFEST" | cut -d' ' -f1)"
  if [ "$actual" != "$MONTANA_MANIFEST_SHA256" ]; then
    echo "[entrypoint] FATAL: manifest sha256 $actual != pinned $MONTANA_MANIFEST_SHA256"
    exit 1
  fi
  echo "[entrypoint] manifest sha256 verified: $actual"
fi

# 3. Start the node.
# The node requires --listen and --genesis-manifest TOGETHER (cross-machine mode)
# or NEITHER (singleton mode). Never --listen alone.
if [ -f "$MANIFEST" ]; then
  set -- start --data-dir "$DATA_DIR" --listen "$LISTEN" --genesis-manifest "$MANIFEST"
  echo "[entrypoint] cross-machine mode"
else
  set -- start --data-dir "$DATA_DIR"
  echo "[entrypoint] singleton mode — no manifest, no --listen"
fi
# TEST-ONLY: deterministic D override. All nodes in a test cohort MUST use the
# same value or they fork. Unset in production (D = params.d0 from Genesis Decree).
if [ -n "${MONTANA_D_TEST_OVERRIDE:-}" ]; then
  set -- "$@" --d-test-override "$MONTANA_D_TEST_OVERRIDE"
  echo "[entrypoint] TEST-ONLY d-test-override=$MONTANA_D_TEST_OVERRIDE"
fi

# No unsolicited site report: the node's identity, label, location and state
# stay with its operator. This does not erase earlier disclosures.
exec runuser -u montana -- /usr/local/bin/montana-node "$@"
