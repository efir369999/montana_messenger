#!/bin/bash
# A sovereign VLESS-REALITY node on one Ubuntu/Debian server. Idempotent.
# Run as root: SNI=www.example.com DEST=www.example.com:443 TRUSTED_IPS="your.ip" bash install.sh
set -euo pipefail
SNI="${SNI:-}"; DEST="${DEST:-}"; PORT="${PORT:-443}"
UUID="${UUID:-}"; PRIV="${PRIV:-}"; SID="${SID:-}"; TRUSTED_IPS="${TRUSTED_IPS:-}"
[ -n "$SNI" ] && [ -n "$DEST" ] || { printf 'ERROR: set SNI and DEST (README, step 2)\n'; exit 1; }
[ "$(id -u)" = 0 ] || { printf 'ERROR: run as root\n'; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; CFG="$HERE/config"; DN=/dev/null; KEYS=/root/vpn-keys.env
say() { printf '%s\n' "$*"; }
field() { awk -F': ' -v w="$1" 'index(tolower($1), w) {print $2; exit}'; }
say "== sovereign VPN node: SNI=$SNI DEST=$DEST PORT=$PORT =="

say "[1/9] packages and Xray"
apt-get update -qq >"$DN" 2>&1 || true
apt-get install -y -qq curl iproute2 iptables ufw fail2ban openssl >"$DN" 2>&1
command -v xray >"$DN" 2>&1 || bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >"$DN"
install -d /var/log/xray /usr/local/etc/xray /etc/systemd/system/xray.service.d

# Keys are born here, kept here (0600), and reused on the next run unless given explicitly.
if [ -f "$KEYS" ]; then . "$KEYS"; fi
[ -n "$UUID" ] || UUID="$(xray uuid)"
[ -n "$PRIV" ] || PRIV="$(xray x25519 | field priv)"
PUB="$(xray x25519 -i "$PRIV" | field pub)"
[ -n "$PUB" ] || PUB="$(xray x25519 -i "$PRIV" | field password)"
[ -n "$SID" ] || SID="$(openssl rand -hex 8)"
umask 077; printf 'UUID=%s\nPRIV=%s\nSID=%s\n' "$UUID" "$PRIV" "$SID" > "$KEYS"; umask 022

say "[2/9] kernel profile"
install -m 0644 "$CFG/99-vpn.conf" /etc/sysctl.d/99-vpn.conf
sysctl --system >"$DN"

say "[3/9] Xray config"
sed -e "s|__SNI__|$SNI|g" -e "s|__DEST__|$DEST|g" -e "s|__PORT__|$PORT|g" -e "s|__UUID__|$UUID|g" \
    -e "s|__PRIVATE_KEY__|$PRIV|g" -e "s|__SHORT_ID__|$SID|g" "$CFG/xray.template.json" > /usr/local/etc/xray/config.json
xray -test -confdir /usr/local/etc/xray/ >"$DN" || { say "ERROR: the Xray config does not validate"; exit 1; }

say "[4/9] systemd hardening"
install -m 0644 "$CFG/xray-hardening.conf" /etc/systemd/system/xray.service.d/hardening.conf

say "[5/9] MSS clamp and IPv6 egress block"
install -m 0644 "$CFG/vpn-mss.service" "$CFG/vpn-ipv6kill.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now vpn-mss vpn-ipv6kill >"$DN" 2>&1 || true

say "[6/9] firewall"
ufw allow 22/tcp >"$DN"; ufw limit 22/tcp >"$DN"; ufw allow "$PORT"/tcp >"$DN"; ufw --force enable >"$DN"

say "[7/9] fail2ban"
sed "s|__TRUSTED_IPS__|$TRUSTED_IPS|" "$CFG/fail2ban-jail.local" > /etc/fail2ban/jail.local
[ -n "$TRUSTED_IPS" ] || say "  WARNING: TRUSTED_IPS is empty; fail2ban may ban your own SSH access"
systemctl enable --now fail2ban >"$DN" 2>&1 || true
systemctl restart fail2ban >"$DN" 2>&1 || true

say "[8/9] watchdog"
sed "s|__PORT__|$PORT|g" "$CFG/xray-guardian.sh" > /usr/local/bin/xray-guardian.sh
chmod 0755 /usr/local/bin/xray-guardian.sh
( crontab -l 2>"$DN" | grep -v xray-guardian || true; say "*/2 * * * * /usr/local/bin/xray-guardian.sh" ) | crontab -

say "[9/9] start and check"
systemctl enable xray >"$DN" 2>&1 || true
systemctl restart xray
say "  xray: $(systemctl is-active xray)"
say "  congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)"
say "  tcp_retries2: $(sysctl -n net.ipv4.tcp_retries2)"
IP4="$(ip -4 route get 1.1.1.1 | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')"
LINK="vless://$UUID@$IP4:$PORT?flow=xtls-rprx-vision&type=tcp&security=reality&fp=safari&sni=$SNI&pbk=$PUB&sid=$SID#my-node"
umask 077; say "$LINK" > /root/vpn-client-link.txt; umask 022
say "== done. The client link (a secret; also in /root/vpn-client-link.txt): =="
say "$LINK"
case "$IP4" in
  10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|192.168.*|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*)
    say "  WARNING: $IP4 is a private address; the provider must give this server a public IPv4 (README, step 1)";;
esac
