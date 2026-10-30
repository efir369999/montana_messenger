#!/bin/bash
# MONTANA -- YOUR OWN NODE. The door of a machine you own: the copies of your whole phone and every file of your chats, in sealed
# pieces, on the shelf only your 24 words open. The machine sees names and sealed bytes, never a key, a word or a list of people.
#
# One script, two roads (the same bytes the app carries, Code/Node):
#   from the app -- Settings, Your node: the address, the login and the password; the app writes the door over SSH and runs this;
#   by hand, on a clean Debian or Ubuntu machine, as root, beside montana-home-node.py:
#       sudo bash install.sh <the address or the name of this machine>
# It makes the user montana and its folders, the unit montana-node-store (the shelf: MONTANA_CAPS=vault), a certificate of the
# machine's own on port 8463, and prints its SHA-256 fingerprint -- the one trust the phone keeps.
set -e
IP="$1"
[ -n "$IP" ] || { echo "usage: sudo bash install.sh <address or name>"; exit 2; }
command -v python3 >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq python3 openssl; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -f "$HERE/montana-home-node.py" ]; then
  mkdir -p /opt/montana-node-store
  install -m 644 "$HERE/montana-home-node.py" /opt/montana-node-store/montana-node-store.py
fi
[ -f /opt/montana-node-store/montana-node-store.py ] || { echo "the door is not here: run this beside montana-home-node.py"; exit 2; }
id montana 2>/dev/null || useradd -r -m -d /var/lib/montana-node-wake -s /usr/sbin/nologin montana
runuser -u montana -- mkdir -p /var/lib/montana-node-wake/blobs /var/lib/montana-node-wake/vault /var/lib/montana-node-wake/tls
python3 - <<'PYEOF'
import os
u = '/etc/systemd/system/montana-node-store.service'
want = {'VAULT_DIR': '/var/lib/montana-node-wake/vault', 'VAULT_TLS_CERT': '/var/lib/montana-node-wake/tls/cert.pem',
        'VAULT_TLS_KEY': '/var/lib/montana-node-wake/tls/key.pem', 'STORE_TLS_PORT': '8463',
        'STORE_DB': '/var/lib/montana-node-wake/tokens.db', 'WAKE_BLOBS': '/var/lib/montana-node-wake/blobs'}
if os.path.exists(u):
    rows = open(u).read().split(chr(10))
    env = {}
    for r in rows:
        if r.startswith('Environment='):
            k, _, v = r[12:].partition('=')
            env[k] = v
    caps = [c for c in env.get('MONTANA_CAPS', '').split(',') if c]
    if 'vault' not in caps: caps.append('vault')
    env['MONTANA_CAPS'] = ','.join(caps)
    for k, v in want.items():
        if k not in env: env[k] = v
    out = []
    for r in rows:
        if r.startswith('Environment='): continue
        out.append(r)
        if r.strip() == '[Service]':
            for k, v in env.items(): out.append('Environment=' + k + '=' + v)
    open(u, 'w').write(chr(10).join(out))
else:
    env = {'MONTANA_CAPS': 'vault'}
    env.update(want)
    text = ['[Unit]', 'Description=Montana node store (the shelf of the whole phone)', 'After=network.target', '', '[Service]']
    text += ['Environment=' + k + '=' + v for k, v in env.items()]
    text += ['User=montana', 'ExecStart=/usr/bin/python3 /opt/montana-node-store/montana-node-store.py', 'Restart=always',
             'RestartSec=2', 'LimitNOFILE=65536', '', '[Install]', 'WantedBy=multi-user.target', '']
    open(u, 'w').write(chr(10).join(text))
PYEOF
if [ ! -f /var/lib/montana-node-wake/tls/key.pem ]; then
  case "$IP" in *[a-zA-Z]*) SAN="DNS:$IP";; *) SAN="IP:$IP";; esac
  runuser -u montana -- sh -c "umask 077; openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 -keyout /var/lib/montana-node-wake/tls/key.pem -out /var/lib/montana-node-wake/tls/cert.pem -subj /CN=montana-node -addext subjectAltName=$SAN" 2>/dev/null
fi
command -v ufw >/dev/null 2>&1 && ufw allow 8463/tcp >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable montana-node-store >/dev/null 2>&1 || true
systemctl restart montana-node-store
sleep 1
systemctl is-active montana-node-store
openssl x509 -in /var/lib/montana-node-wake/tls/cert.pem -noout -fingerprint -sha256
