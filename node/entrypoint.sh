#!/bin/bash
# Montana node entrypoint (node/ kit). It differs from the project entrypoint
# Code/docker/runtime/node-entrypoint.sh on four points:
#   1. The 24 recovery words never reach stdout or the container log: the whole
#      output of `montana-node init` goes only into mnemonic.txt (0600, montana).
#   2. Nothing is reported to anyone unless the owner sets MONTANA_REPORT_URL.
#   3. MONTANA_ENABLE_CANDIDATE=1 starts the node with --enable-candidate.
#   4. restore-words.txt on a fresh volume restores that identity through stdin.
#
# Env:
#   MONTANA_LISTEN             default /ip4/0.0.0.0/tcp/8444 (used only with a manifest)
#   MONTANA_GENESIS_MANIFEST   manifest path (default /etc/montana/genesis-manifest.json)
#   MONTANA_MANIFEST_SHA256    if set, refuse to start unless the manifest sha matches
#   MONTANA_ENABLE_CANDIDATE   "1" = start with --enable-candidate
#   MONTANA_REPORT_URL         unset or empty = no report is sent anywhere
#   MONTANA_ALIAS, MONTANA_LABEL, MONTANA_COUNTRY   used only when MONTANA_REPORT_URL is set
set -eu

NODE="/usr/local/bin/montana-node"
DATA_DIR="/var/lib/montana"
WORDS="$DATA_DIR/mnemonic.txt"
RESTORE="$DATA_DIR/restore-words.txt"
RESTORE_USED="$DATA_DIR/restore-words.used"
MANIFEST="${MONTANA_GENESIS_MANIFEST:-/etc/montana/genesis-manifest.json}"
LISTEN="${MONTANA_LISTEN:-/ip4/0.0.0.0/tcp/8444}"

mkdir -p "$DATA_DIR"
chown -R montana:montana "$DATA_DIR"
chmod 0700 "$DATA_DIR"

# 1. Identity, once per data volume. init prints the words to /dev/tty when it can
# open one and to stdout otherwise; setsid leaves it without a controlling terminal,
# so the words go to stdout, and stdout goes only into the 0600 file.
# With restore-words.txt on a fresh volume, init recovers that identity instead; the
# words reach it only through stdin (--mnemonic-stdin), never through a command line.
if [ ! -f "$DATA_DIR/identity.bin" ]; then
  install -m 0600 -o montana -g montana /dev/null "$WORDS"
  if [ -f "$RESTORE" ]; then
    echo "[entrypoint] first run on this volume: restoring the node identity from restore-words.txt"
    chmod 0600 "$RESTORE"
    if tr -s "[:space:]" " " <"$RESTORE" | runuser -u montana -- setsid -w "$NODE" init --data-dir "$DATA_DIR" --mnemonic-stdin >>"$WORDS"; then
      used="$RESTORE_USED"
      [ -e "$used" ] && used="$RESTORE_USED.$(date +%s)"
      mv "$RESTORE" "$used"
      echo "[entrypoint] identity restored; restore-words.txt renamed to $(basename "$used")"
    else
      echo "[entrypoint] FATAL: restore failed (error above); restore-words.txt kept, no identity written"
      exit 1
    fi
  else
    echo "[entrypoint] first run on this volume: generating the node identity"
    runuser -u montana -- setsid -w "$NODE" init --data-dir "$DATA_DIR" >>"$WORDS" </dev/null
  fi
  echo "[entrypoint] identity created; the recovery words are in $WORDS (0600), read them once (README.md)"
elif [ -f "$RESTORE" ]; then
  echo "[entrypoint] restore-words.txt ignored: this volume already holds an identity"
fi

# 2. Optional manifest pin: refuse to start on sha mismatch.
if [ -f "$MANIFEST" ] && [ -n "${MONTANA_MANIFEST_SHA256:-}" ]; then
  actual="$(sha256sum "$MANIFEST" | cut -d" " -f1)"
  if [ "$actual" != "$MONTANA_MANIFEST_SHA256" ]; then
    echo "[entrypoint] FATAL: manifest sha256 $actual != pinned $MONTANA_MANIFEST_SHA256"
    exit 1
  fi
  echo "[entrypoint] manifest sha256 verified: $actual"
fi

# 3. The node requires --listen and --genesis-manifest together (cross-machine
# mode) or neither (singleton mode).
if [ -f "$MANIFEST" ]; then
  set -- start --data-dir "$DATA_DIR" --listen "$LISTEN" --genesis-manifest "$MANIFEST"
  echo "[entrypoint] cross-machine mode: manifest $MANIFEST, listen $LISTEN"
else
  set -- start --data-dir "$DATA_DIR"
  echo "[entrypoint] singleton mode: no manifest, no --listen"
fi
if [ "${MONTANA_ENABLE_CANDIDATE:-}" = "1" ]; then
  set -- "$@" --enable-candidate
  echo "[entrypoint] candidate enabled (--enable-candidate)"
fi

# 4. A report leaves the server only when its owner named the address.
REPORT_URL="${MONTANA_REPORT_URL:-}"
if [ -n "$REPORT_URL" ]; then
  ALIAS="${MONTANA_ALIAS:-$(runuser -u montana -- "$NODE" inspect --data-dir "$DATA_DIR" 2>/dev/null | awk "/^node_id/{print substr(\$3,1,8)}")}"
  LABEL="${MONTANA_LABEL:-$ALIAS}"
  COUNTRY="${MONTANA_COUNTRY:-}"
  echo "[entrypoint] reporting to $REPORT_URL every 30 s (set by the owner)"
  (
    while true; do
      st="$(runuser -u montana -- "$NODE" status --data-dir "$DATA_DIR" 2>/dev/null)"
      win="$(printf "%s" "$st" | grep current_window | grep -oE "[0-9]+" | head -1)"
      ph="$(printf "%s" "$st" | awk "/^phase/{print \$3; exit}")"
      nt="$(printf "%s" "$st" | grep -i "NodeTable" | grep -oE "[0-9]+" | head -1)"
      [ -n "$ph" ] && curl -sf -m 8 -X POST -H "Content-Type: application/json" \
        --data "{\"node\":\"$ALIAS\",\"label\":\"$LABEL\",\"country\":\"$COUNTRY\",\"current_window\":${win:-0},\"phase\":\"$ph\",\"node_table\":${nt:-0},\"ok\":true}" \
        "$REPORT_URL" >/dev/null 2>&1 || true
      sleep 30
    done
  ) &
else
  echo "[entrypoint] no report: MONTANA_REPORT_URL is not set"
fi

exec runuser -u montana -- "$NODE" "$@"
